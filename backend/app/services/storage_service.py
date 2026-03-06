import shutil
from abc import ABC, abstractmethod
from pathlib import Path
from typing import BinaryIO

from app.core.config import settings


class StorageService(ABC):
    @abstractmethod
    async def upload(self, file: BinaryIO, path: str) -> str:
        ...

    @abstractmethod
    async def download(self, path: str) -> bytes:
        ...

    @abstractmethod
    async def delete(self, path: str) -> bool:
        ...

    @abstractmethod
    def get_url(self, path: str) -> str:
        ...


class LocalStorageService(StorageService):
    def __init__(self):
        self.base = Path(settings.LOCAL_STORAGE_PATH)
        self.base.mkdir(parents=True, exist_ok=True)

    async def upload(self, file: BinaryIO, path: str) -> str:
        dest = self.base / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as f:
            shutil.copyfileobj(file, f)
        return path

    async def download(self, path: str) -> bytes:
        with open(self.base / path, "rb") as f:
            return f.read()

    async def delete(self, path: str) -> bool:
        target = self.base / path
        if target.exists():
            target.unlink()
            return True
        return False

    def get_url(self, path: str) -> str:
        return f"/files/{path}"


class S3StorageService(StorageService):
    def __init__(self):
        import boto3
        self.client = boto3.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT,
            aws_access_key_id=settings.S3_ACCESS_KEY,
            aws_secret_access_key=settings.S3_SECRET_KEY,
            region_name=settings.S3_REGION,
        )
        self.bucket = settings.S3_BUCKET

    async def upload(self, file: BinaryIO, path: str) -> str:
        self.client.upload_fileobj(file, self.bucket, path)
        return path

    async def download(self, path: str) -> bytes:
        resp = self.client.get_object(Bucket=self.bucket, Key=path)
        return resp["Body"].read()

    async def delete(self, path: str) -> bool:
        self.client.delete_object(Bucket=self.bucket, Key=path)
        return True

    def get_url(self, path: str) -> str:
        if settings.S3_PUBLIC_URL:
            return f"{settings.S3_PUBLIC_URL}/{path}"
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": path},
            ExpiresIn=3600,
        )


def get_storage_service() -> StorageService:
    if settings.STORAGE_TYPE == "s3":
        return S3StorageService()
    return LocalStorageService()
