# backend/app/services/blob_storage.py
"""
Pure byte-layer storage for content-addressed blobs.
Knows about filesystem/S3 backends. Knows nothing about the database.
Addresses all files by SHA-256 hash.
"""

import hashlib
import io
import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import AsyncIterator, BinaryIO

from app.core.config import settings


class BlobTooLargeError(Exception):
    """Raised when streamed blob data exceeds the configured size limit."""

    def __init__(self, actual: int, limit: int):
        """Initializes the blob size error.

        Args:
            actual: Actual byte count observed.
            limit: Maximum allowed byte count.
        """
        self.actual = actual
        self.limit = limit
        super().__init__(f"Blob size {actual} exceeds limit {limit}")


class BlobNotFoundError(Exception):
    """Raised when a blob hash cannot be found in the backing storage."""

    pass


@dataclass(frozen=True)
class BlobPutResult:
    """Result returned after writing blob bytes to temporary storage."""

    blob_hash: str
    byte_size: int
    mime_type: str
    temp_path: str  # caller decides whether to move or discard


class LocalBlobStorage:
    """Content-addressed local filesystem storage."""

    def __init__(self):
        """Initializes the local blob directory."""
        self.base = Path(settings.LOCAL_STORAGE_PATH) / "blobs"
        self.base.mkdir(parents=True, exist_ok=True)

    def path_for(self, blob_hash: str) -> str:
        """Return the absolute content-addressed path for one blob hash."""
        return str((self.base / blob_hash[:2] / blob_hash[2:4] / blob_hash).resolve())

    async def put_to_temp(
        self,
        data: BinaryIO,
        *,
        claimed_mime_type: str,
        max_size: int,
        chunk_size: int = 65536,
    ) -> BlobPutResult:
        """
        Stream-read data, compute SHA-256, write to temp file.
        Returns BlobPutResult with temp_path. Caller is responsible
        for either moving temp to final location or deleting it.
        """
        hasher = hashlib.sha256()
        size = 0
        tmp = tempfile.NamedTemporaryFile(
            delete=False,
            dir=str(self.base),
            prefix="_upload_",
        )
        try:
            while True:
                chunk = data.read(chunk_size)
                if not chunk:
                    break
                size += len(chunk)
                if size > max_size:
                    tmp.close()
                    os.unlink(tmp.name)
                    raise BlobTooLargeError(size, max_size)
                hasher.update(chunk)
                tmp.write(chunk)
            tmp.close()
        except BlobTooLargeError:
            raise
        except Exception:
            tmp.close()
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            raise

        return BlobPutResult(
            blob_hash=hasher.hexdigest(),
            byte_size=size,
            mime_type=claimed_mime_type or "application/octet-stream",
            temp_path=tmp.name,
        )

    def move_temp_to_final(self, temp_path: str, blob_hash: str) -> None:
        """Move or copy a temp file into its content-addressed location."""
        final = self.path_for(blob_hash)
        os.makedirs(os.path.dirname(final), exist_ok=True)
        try:
            os.replace(temp_path, final)
        except PermissionError:
            # Some Windows sandboxed runs allow writing files but reject rename
            # or delete operations on NamedTemporaryFile outputs. Copying keeps
            # the blob addressable even when temp cleanup has to be skipped.
            with open(temp_path, "rb") as source, open(final, "wb") as target:
                shutil.copyfileobj(source, target)
            try:
                os.unlink(temp_path)
            except PermissionError:
                pass

    def exists(self, blob_hash: str) -> bool:
        """Checks whether a blob file exists locally.

        Args:
            blob_hash: SHA-256 blob hash.

        Returns:
            True when the content-addressed file exists.
        """
        return os.path.exists(self.path_for(blob_hash))

    async def get_bytes(self, blob_hash: str) -> bytes:
        """Reads a local blob into memory.

        Args:
            blob_hash: SHA-256 blob hash.

        Returns:
            Blob bytes.

        Raises:
            BlobNotFoundError: If the blob file does not exist.
        """
        path = self.path_for(blob_hash)
        if not os.path.exists(path):
            raise BlobNotFoundError(blob_hash)
        with open(path, "rb") as f:
            return f.read()

    async def open_stream(self, blob_hash: str):
        """Generator that yields chunks for StreamingResponse."""
        path = self.path_for(blob_hash)
        if not os.path.exists(path):
            raise BlobNotFoundError(blob_hash)

        def _iter():
            """Yields blob file chunks."""
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    yield chunk

        return _iter()

    async def physical_delete(self, blob_hash: str) -> None:
        """Physically deletes a local blob file if present.

        Args:
            blob_hash: SHA-256 blob hash.
        """
        path = self.path_for(blob_hash)
        if os.path.exists(path):
            os.unlink(path)


class S3BlobStorage:
    """Content-addressed S3 storage."""

    def __init__(self):
        """Initializes the S3 client and bucket settings."""
        import boto3
        self.client = boto3.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT,
            aws_access_key_id=settings.S3_ACCESS_KEY,
            aws_secret_access_key=settings.S3_SECRET_KEY,
            region_name=settings.S3_REGION,
        )
        self.bucket = settings.S3_BUCKET

    def path_for(self, blob_hash: str) -> str:
        """Returns the S3 object key for one blob hash.

        Args:
            blob_hash: SHA-256 blob hash.

        Returns:
            S3 object key.
        """
        return f"blobs/{blob_hash[:2]}/{blob_hash[2:4]}/{blob_hash}"

    async def put_to_temp(self, data, *, claimed_mime_type, max_size, chunk_size=65536):
        """Uploads streamed bytes to S3 and returns blob metadata.

        Args:
            data: Binary stream to read.
            claimed_mime_type: MIME type reported by the caller.
            max_size: Maximum allowed byte size.
            chunk_size: Read chunk size.

        Returns:
            Blob put result.
        """
        hasher = hashlib.sha256()
        buf = io.BytesIO()
        size = 0
        while True:
            chunk = data.read(chunk_size)
            if not chunk:
                break
            size += len(chunk)
            if size > max_size:
                raise BlobTooLargeError(size, max_size)
            hasher.update(chunk)
            buf.write(chunk)
        blob_hash = hasher.hexdigest()
        buf.seek(0)

        key = self.path_for(blob_hash)
        try:
            self.client.head_object(Bucket=self.bucket, Key=key)
        except self.client.exceptions.ClientError:
            self.client.upload_fileobj(buf, self.bucket, key)

        return BlobPutResult(
            blob_hash=blob_hash,
            byte_size=size,
            mime_type=claimed_mime_type or "application/octet-stream",
            temp_path="",
        )

    def move_temp_to_final(self, temp_path: str, blob_hash: str) -> None:
        """No-ops because S3 upload already writes to the final key.

        Args:
            temp_path: Unused temp path.
            blob_hash: SHA-256 blob hash.
        """
        pass  # S3 put_to_temp already uploads

    def exists(self, blob_hash: str) -> bool:
        """Checks whether a blob object exists in S3.

        Args:
            blob_hash: SHA-256 blob hash.

        Returns:
            True when S3 has the blob object.
        """
        try:
            self.client.head_object(Bucket=self.bucket, Key=self.path_for(blob_hash))
            return True
        except Exception:
            return False

    async def get_bytes(self, blob_hash: str) -> bytes:
        """Reads a blob object from S3 into memory.

        Args:
            blob_hash: SHA-256 blob hash.

        Returns:
            Blob bytes.
        """
        resp = self.client.get_object(Bucket=self.bucket, Key=self.path_for(blob_hash))
        return resp["Body"].read()

    async def open_stream(self, blob_hash: str):
        """Opens a streaming iterator for a blob object in S3.

        Args:
            blob_hash: SHA-256 blob hash.

        Returns:
            Iterator yielding byte chunks.
        """
        resp = self.client.get_object(Bucket=self.bucket, Key=self.path_for(blob_hash))
        def _iter():
            """Yields S3 response chunks."""
            for chunk in resp["Body"].iter_chunks(65536):
                yield chunk
        return _iter()

    async def physical_delete(self, blob_hash: str) -> None:
        """Deletes a blob object from S3.

        Args:
            blob_hash: SHA-256 blob hash.
        """
        self.client.delete_object(Bucket=self.bucket, Key=self.path_for(blob_hash))

    def get_presigned_url(self, blob_hash: str, expires_in: int = 3600) -> str:
        """Builds a temporary URL for reading an S3 blob.

        Args:
            blob_hash: SHA-256 blob hash.
            expires_in: Expiration time in seconds.

        Returns:
            Presigned S3 URL.
        """
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": self.path_for(blob_hash)},
            ExpiresIn=expires_in,
        )


def get_blob_storage():
    """Factory: returns the correct BlobStorage implementation."""
    if settings.STORAGE_TYPE == "s3":
        return S3BlobStorage()
    return LocalBlobStorage()
