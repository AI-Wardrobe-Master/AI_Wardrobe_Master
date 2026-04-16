# backend/app/services/blob_service.py
"""
Database-backed blob registry with reference counting.
Manages the blobs table, advisory locks for concurrency safety,
and lifecycle (ingest, addref, release).
"""

import io
import logging
import os
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.blob import Blob
from app.services.blob_storage import (
    BlobNotFoundError,
    BlobPutResult,
    get_blob_storage,
)

logger = logging.getLogger(__name__)


def _lock_hash(db: Session, blob_hash: str) -> None:
    """Acquire a transaction-scoped advisory lock keyed on the blob hash."""
    db.execute(
        text("SELECT pg_advisory_xact_lock(hashtext(:h))"),
        {"h": blob_hash},
    )


class BlobService:
    def __init__(self):
        self.storage = get_blob_storage()

    async def ingest_upload(
        self,
        db: Session,
        data: io.BytesIO | object,
        *,
        claimed_mime_type: str,
        max_size: int,
    ) -> Blob:
        """
        Full upload: hash bytes, persist to storage, upsert blobs row.
        Returns the Blob row with ref_count already incremented.
        Caller must commit the transaction.
        """
        result: BlobPutResult = await self.storage.put_to_temp(
            data,
            claimed_mime_type=claimed_mime_type,
            max_size=max_size,
        )

        try:
            _lock_hash(db, result.blob_hash)

            existing = (
                db.query(Blob)
                .filter(Blob.blob_hash == result.blob_hash)
                .first()
            )
            now = datetime.now(timezone.utc)

            if existing is not None:
                existing.ref_count += 1
                existing.last_referenced_at = now
                existing.pending_delete_at = None
                # Discard temp file — content already stored
                if result.temp_path and os.path.exists(result.temp_path):
                    os.unlink(result.temp_path)
                db.flush()
                return existing
            else:
                # Move temp to final location
                if result.temp_path:
                    self.storage.move_temp_to_final(
                        result.temp_path, result.blob_hash
                    )
                blob = Blob(
                    blob_hash=result.blob_hash,
                    byte_size=result.byte_size,
                    mime_type=result.mime_type,
                    ref_count=1,
                    first_seen_at=now,
                    last_referenced_at=now,
                    pending_delete_at=None,
                )
                db.add(blob)
                db.flush()
                return blob
        except Exception:
            if result.temp_path and os.path.exists(result.temp_path):
                os.unlink(result.temp_path)
            raise

    def addref(self, db: Session, blob_hash: str) -> None:
        """
        For import flow: bytes already exist, only increment refcount.
        """
        _lock_hash(db, blob_hash)
        blob = db.query(Blob).filter(Blob.blob_hash == blob_hash).first()
        if blob is None:
            raise BlobNotFoundError(blob_hash)
        blob.ref_count += 1
        blob.last_referenced_at = datetime.now(timezone.utc)
        blob.pending_delete_at = None
        db.flush()

    def release(self, db: Session, blob_hash: str) -> None:
        """
        Decrement refcount. If it reaches 0, mark for GC.
        """
        blob = db.query(Blob).filter(Blob.blob_hash == blob_hash).first()
        if blob is None:
            logger.warning("release() called for unknown blob %s", blob_hash)
            return
        blob.ref_count = max(0, blob.ref_count - 1)
        if blob.ref_count == 0:
            blob.pending_delete_at = datetime.now(timezone.utc)
        db.flush()


def get_blob_service() -> BlobService:
    return BlobService()
