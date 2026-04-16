# CAS Storage Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace path-based file storage with content-addressed storage (SHA-256 dedup), add card-pack import/un-import flows, add clothing-item delete, and implement async blob GC.

**Architecture:** All file bytes are stored once by content hash in a `blobs` table + filesystem sharded `blobs/{h[:2]}/{h[2:4]}/{h}`. Business tables reference `blob_hash CHAR(64) FK` instead of `storage_path TEXT`. BlobService manages refcounting. BlobStorage handles physical bytes. Import creates snapshot clothing_items rows with shared blob refs. GC sweeps orphaned blobs after 24h grace.

**Tech Stack:** Python 3.11, FastAPI, SQLAlchemy 2.0, Alembic, PostgreSQL 16, Celery+Redis, hashlib.sha256, pg_advisory_xact_lock

**Spec:** `docs/superpowers/specs/2026-04-15-cas-storage-refactor-design.md`

**Pre-requisite:** `docker compose down -v` to wipe dev data before running migrations.

---

## File Structure

### New files (10)

| Path | Responsibility |
|------|----------------|
| `backend/app/models/blob.py` | `Blob` SQLAlchemy model (PK=blob_hash CHAR64, ref_count, pending_delete_at) |
| `backend/app/models/card_pack_import.py` | `CardPackImport` model (user_id FK, card_pack_id FK, unique constraint) |
| `backend/app/services/blob_storage.py` | Pure byte-layer: `LocalBlobStorage` + `S3BlobStorage`, hash-addressed put/get/delete |
| `backend/app/services/blob_service.py` | DB+refcount layer: `ingest_upload`, `addref`, `release`, advisory locks |
| `backend/app/api/v1/files.py` | Business-path file serving router (mounted at `/files`, resolves blob_hash internally) |
| `backend/app/api/v1/imports.py` | `POST /imports/card-pack`, `DELETE /imports/card-pack/{pack_id}` |
| `backend/app/schemas/imports.py` | `ImportCardPackRequest`, `ImportCardPackResponse` |
| `backend/alembic/versions/20260415_000010_cas_storage_refactor.py` | Single monolithic migration |
| `backend/scripts/verify_blob_refcount.py` | Operational reconciliation tool |
| `backend/tests/test_blob_service.py` | Tests for BlobStorage + BlobService |

### Modified files (22)

| Path | What changes |
|------|-------------|
| `backend/app/models/clothing_item.py` | `Image.storage_path` -> `blob_hash`; `Model3D.storage_path` -> `blob_hash`; drop `Model3D.file_size`; `ClothingItem` adds `imported_from_card_pack_id`, `imported_from_creator_item_id` |
| `backend/app/models/creator.py` | `CreatorItemImage.storage_path` -> `blob_hash`; `CreatorItemModel3D.storage_path` -> `blob_hash`; drop `CreatorItemModel3D.file_size`; `CardPack.cover_image_storage_path` -> `cover_image_blob_hash` |
| `backend/app/models/styled_generation.py` | 3 path columns -> blob_hash columns |
| `backend/app/models/outfit_preview.py` | `OutfitPreviewTask`: 2 path -> blob_hash; `OutfitPreviewTaskItem`: 1 path -> blob_hash; `Outfit`: 1 path -> blob_hash |
| `backend/app/models/__init__.py` | Export `Blob`, `CardPackImport` |
| `backend/alembic/env.py` | Import `Blob`, `CardPackImport` |
| `backend/app/services/clothing_pipeline.py` | All storage.upload/download -> blob_service/blob_storage; Image/Model3D creation uses blob_hash |
| `backend/app/services/creator_pipeline.py` | Same pattern as clothing_pipeline |
| `backend/app/services/styled_generation_pipeline.py` | storage -> blob_service for selfie/result uploads; reads via blob_storage.get_bytes |
| `backend/app/services/outfit_preview_service.py` | storage -> blob_service for person image upload + result storage |
| `backend/app/services/storage_service.py` | **DELETE** this file (superseded by blob_storage.py + blob_service.py) |
| `backend/app/api/v1/clothing.py` | POST: use blob_service; add DELETE endpoint; URL construction via `/files/clothing-items/...` |
| `backend/app/api/v1/creator_items.py` | POST: use blob_service; DELETE: add blob release; URL construction |
| `backend/app/api/v1/card_packs.py` | DELETE: check imports, release cover blob; URL construction |
| `backend/app/api/v1/styled_generation.py` | POST: use blob_service for selfie; URL construction |
| `backend/app/api/v1/outfit_preview.py` | URL construction via `/files/...` |
| `backend/app/api/v1/router.py` | Include `imports` router |
| `backend/app/main.py` | Remove StaticFiles mount; include `files` router at `/files` |
| `backend/app/core/celery_app.py` | Add `beat_schedule` for GC |
| `backend/app/tasks.py` | Add `gc_sweep` task |
| `docker-compose.yml` | Add `celery-beat` service |
| `backend/app/core/config.py` | Remove old `LOCAL_STORAGE_PATH` usage in favor of `BLOB_STORAGE_PATH` (or keep the same setting name; the meaning changes from "path-based root" to "blobs root") |

---

## Task 1: Blob + CardPackImport models

**Files:**
- Create: `backend/app/models/blob.py`
- Create: `backend/app/models/card_pack_import.py`
- Modify: `backend/app/models/__init__.py`
- Modify: `backend/alembic/env.py`

- [ ] **Step 1: Create Blob model**

```python
# backend/app/models/blob.py
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Column,
    DateTime,
    Index,
    Integer,
    String,
    Text,
)

from app.db.base import Base


class Blob(Base):
    __tablename__ = "blobs"

    blob_hash = Column(String(64), primary_key=True)
    byte_size = Column(BigInteger, nullable=False)
    mime_type = Column(String(100), nullable=False)
    ref_count = Column(Integer, nullable=False, default=0)
    first_seen_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    last_referenced_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    pending_delete_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint("ref_count >= 0", name="ck_blob_ref_count"),
        Index(
            "idx_blobs_pending_delete",
            "pending_delete_at",
            postgresql_where=Column("pending_delete_at").isnot(None),
        ),
    )
```

- [ ] **Step 2: Create CardPackImport model**

```python
# backend/app/models/card_pack_import.py
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class CardPackImport(Base):
    __tablename__ = "card_pack_imports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    card_pack_id = Column(
        UUID(as_uuid=True),
        ForeignKey("card_packs.id", ondelete="RESTRICT"),
        nullable=False,
    )
    imported_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        UniqueConstraint("user_id", "card_pack_id", name="uq_card_pack_imports_user_pack"),
        Index("idx_card_pack_imports_pack", "card_pack_id"),
    )
```

- [ ] **Step 3: Update models/__init__.py**

Add to imports and `__all__`:

```python
from app.models.blob import Blob
from app.models.card_pack_import import CardPackImport
```

Add `"Blob"` and `"CardPackImport"` to `__all__` list.

- [ ] **Step 4: Update alembic/env.py**

Add after the existing model imports:

```python
from app.models.blob import Blob  # noqa: F401
from app.models.card_pack_import import CardPackImport  # noqa: F401
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/models/blob.py backend/app/models/card_pack_import.py \
       backend/app/models/__init__.py backend/alembic/env.py
git commit -m "feat(models): add Blob and CardPackImport models"
```

---

## Task 2: Model field renames (storage_path -> blob_hash)

**Files:**
- Modify: `backend/app/models/clothing_item.py`
- Modify: `backend/app/models/creator.py`
- Modify: `backend/app/models/styled_generation.py`
- Modify: `backend/app/models/outfit_preview.py`

All changes follow the same pattern: replace `storage_path = Column(Text, ...)` with `blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), ...)`.

- [ ] **Step 1: Update clothing_item.py — Image model**

In the `Image` class, replace:
```python
storage_path = Column(Text, nullable=False)
```
with:
```python
blob_hash = Column(
    String(64), ForeignKey("blobs.blob_hash"), nullable=False
)
```

Also remove `file_size` and `mime_type` columns from `Image` (this info is now on `Blob`):
```python
# DELETE these two lines:
file_size = Column(BigInteger, nullable=True)
mime_type = Column(String(50), nullable=True)
```

- [ ] **Step 2: Update clothing_item.py — Model3D model**

In the `Model3D` class, replace:
```python
storage_path = Column(Text, nullable=False)
```
with:
```python
blob_hash = Column(
    String(64), ForeignKey("blobs.blob_hash"), nullable=False
)
```

Remove `file_size` column:
```python
# DELETE this line:
file_size = Column(BigInteger, nullable=True)
```

- [ ] **Step 3: Update clothing_item.py — ClothingItem model**

Add two new columns to `ClothingItem` for import lineage:
```python
imported_from_card_pack_id = Column(
    UUID(as_uuid=True),
    ForeignKey("card_packs.id", ondelete="SET NULL"),
    nullable=True,
)
imported_from_creator_item_id = Column(
    UUID(as_uuid=True),
    ForeignKey("creator_items.id", ondelete="SET NULL"),
    nullable=True,
)
```

Add to `__table_args__`:
```python
Index("idx_clothing_items_imported_from_pack", "imported_from_card_pack_id"),
```

- [ ] **Step 4: Update creator.py — CreatorItemImage**

Same pattern as Image: replace `storage_path` with `blob_hash`, remove `file_size` and `mime_type`.

- [ ] **Step 5: Update creator.py — CreatorItemModel3D**

Same pattern as Model3D: replace `storage_path` with `blob_hash`, remove `file_size`.

- [ ] **Step 6: Update creator.py — CardPack**

Replace:
```python
cover_image_storage_path = Column(Text, nullable=True)
```
with:
```python
cover_image_blob_hash = Column(
    String(64), ForeignKey("blobs.blob_hash"), nullable=True
)
```

- [ ] **Step 7: Update styled_generation.py**

Replace three columns:
```python
# OLD:
selfie_original_path = Column(Text, nullable=False)
selfie_processed_path = Column(Text, nullable=True)
result_image_path = Column(Text, nullable=True)

# NEW:
selfie_original_blob_hash = Column(
    String(64), ForeignKey("blobs.blob_hash"), nullable=False
)
selfie_processed_blob_hash = Column(
    String(64), ForeignKey("blobs.blob_hash"), nullable=True
)
result_image_blob_hash = Column(
    String(64), ForeignKey("blobs.blob_hash"), nullable=True
)
```

- [ ] **Step 8: Update outfit_preview.py**

Replace in `OutfitPreviewTask`:
```python
person_image_path = Column(Text, nullable=False)
# becomes:
person_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)

preview_image_path = Column(Text, nullable=True)
# becomes:
preview_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=True)
```

Replace in `OutfitPreviewTaskItem`:
```python
garment_image_path = Column(Text, nullable=False)
# becomes:
garment_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
```

Replace in `Outfit`:
```python
preview_image_path = Column(Text, nullable=False)
# becomes:
preview_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
```

- [ ] **Step 9: Commit**

```bash
git add backend/app/models/clothing_item.py backend/app/models/creator.py \
       backend/app/models/styled_generation.py backend/app/models/outfit_preview.py
git commit -m "feat(models): rename storage_path columns to blob_hash FK refs"
```

---

## Task 3: Alembic migration

**Files:**
- Create: `backend/alembic/versions/20260415_000010_cas_storage_refactor.py`

- [ ] **Step 1: Write the migration**

```python
"""CAS storage refactor: blobs table, column renames, card_pack_imports

Revision ID: 20260415_000010
Revises: 20260413_000005
Create Date: 2026-04-15
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260415_000010"
down_revision: Union[str, None] = "20260413_000005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Create blobs table
    op.create_table(
        "blobs",
        sa.Column("blob_hash", sa.String(64), primary_key=True),
        sa.Column("byte_size", sa.BigInteger(), nullable=False),
        sa.Column("mime_type", sa.String(100), nullable=False),
        sa.Column("ref_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("first_seen_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.Column("last_referenced_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.Column("pending_delete_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_check_constraint("ck_blob_ref_count", "blobs", "ref_count >= 0")
    op.create_index(
        "idx_blobs_pending_delete", "blobs", ["pending_delete_at"],
        postgresql_where=sa.text("pending_delete_at IS NOT NULL"),
    )

    # 2. Create card_pack_imports table
    op.create_table(
        "card_pack_imports",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("card_pack_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("card_packs.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("imported_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", "card_pack_id", name="uq_card_pack_imports_user_pack"),
    )
    op.create_index("idx_card_pack_imports_pack", "card_pack_imports", ["card_pack_id"])

    # 3. clothing_items: add imported_from columns
    op.add_column("clothing_items",
        sa.Column("imported_from_card_pack_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column("clothing_items",
        sa.Column("imported_from_creator_item_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.create_foreign_key(
        "fk_clothing_items_imported_pack", "clothing_items", "card_packs",
        ["imported_from_card_pack_id"], ["id"], ondelete="SET NULL")
    op.create_foreign_key(
        "fk_clothing_items_imported_creator_item", "clothing_items", "creator_items",
        ["imported_from_creator_item_id"], ["id"], ondelete="SET NULL")
    op.create_index("idx_clothing_items_imported_from_pack", "clothing_items",
                    ["imported_from_card_pack_id"])

    # 4. Column swaps: storage_path -> blob_hash
    COLUMN_SWAPS = [
        ("images", "storage_path", "blob_hash", False),
        ("creator_item_images", "storage_path", "blob_hash", False),
        ("models_3d", "storage_path", "blob_hash", False),
        ("creator_models_3d", "storage_path", "blob_hash", False),
        ("styled_generations", "selfie_original_path", "selfie_original_blob_hash", False),
        ("styled_generations", "selfie_processed_path", "selfie_processed_blob_hash", True),
        ("styled_generations", "result_image_path", "result_image_blob_hash", True),
        ("outfit_preview_tasks", "person_image_path", "person_image_blob_hash", False),
        ("outfit_preview_tasks", "preview_image_path", "preview_image_blob_hash", True),
        ("outfit_preview_task_items", "garment_image_path", "garment_image_blob_hash", False),
        ("outfits", "preview_image_path", "preview_image_blob_hash", False),
        ("card_packs", "cover_image_storage_path", "cover_image_blob_hash", True),
    ]
    for table, old_col, new_col, nullable in COLUMN_SWAPS:
        op.drop_column(table, old_col)
        op.add_column(table, sa.Column(
            new_col, sa.String(64),
            sa.ForeignKey("blobs.blob_hash"),
            nullable=nullable,
        ))

    # 5. Drop redundant file_size and mime_type columns
    op.drop_column("images", "file_size")
    op.drop_column("images", "mime_type")
    op.drop_column("creator_item_images", "file_size")
    op.drop_column("creator_item_images", "mime_type")
    op.drop_column("models_3d", "file_size")
    op.drop_column("creator_models_3d", "file_size")


def downgrade() -> None:
    # Reverse column swaps
    COLUMN_SWAPS = [
        ("images", "blob_hash", "storage_path"),
        ("creator_item_images", "blob_hash", "storage_path"),
        ("models_3d", "blob_hash", "storage_path"),
        ("creator_models_3d", "blob_hash", "storage_path"),
        ("styled_generations", "selfie_original_blob_hash", "selfie_original_path"),
        ("styled_generations", "selfie_processed_blob_hash", "selfie_processed_path"),
        ("styled_generations", "result_image_blob_hash", "result_image_path"),
        ("outfit_preview_tasks", "person_image_blob_hash", "person_image_path"),
        ("outfit_preview_tasks", "preview_image_blob_hash", "preview_image_path"),
        ("outfit_preview_task_items", "garment_image_blob_hash", "garment_image_path"),
        ("outfits", "preview_image_blob_hash", "preview_image_path"),
        ("card_packs", "cover_image_blob_hash", "cover_image_storage_path"),
    ]
    for table, old_col, new_col in COLUMN_SWAPS:
        op.drop_column(table, old_col)
        op.add_column(table, sa.Column(new_col, sa.Text(), nullable=True))

    # Restore file_size / mime_type
    op.add_column("images", sa.Column("file_size", sa.BigInteger(), nullable=True))
    op.add_column("images", sa.Column("mime_type", sa.String(50), nullable=True))
    op.add_column("creator_item_images", sa.Column("file_size", sa.BigInteger(), nullable=True))
    op.add_column("creator_item_images", sa.Column("mime_type", sa.String(50), nullable=True))
    op.add_column("models_3d", sa.Column("file_size", sa.BigInteger(), nullable=True))
    op.add_column("creator_models_3d", sa.Column("file_size", sa.BigInteger(), nullable=True))

    op.drop_index("idx_clothing_items_imported_from_pack", "clothing_items")
    op.drop_constraint("fk_clothing_items_imported_creator_item", "clothing_items", type_="foreignkey")
    op.drop_constraint("fk_clothing_items_imported_pack", "clothing_items", type_="foreignkey")
    op.drop_column("clothing_items", "imported_from_creator_item_id")
    op.drop_column("clothing_items", "imported_from_card_pack_id")

    op.drop_table("card_pack_imports")
    op.drop_table("blobs")
```

- [ ] **Step 2: Commit**

```bash
git add backend/alembic/versions/20260415_000010_cas_storage_refactor.py
git commit -m "feat(migration): add CAS storage refactor migration"
```

---

## Task 4: BlobStorage (byte layer)

**Files:**
- Create: `backend/app/services/blob_storage.py`

- [ ] **Step 1: Write BlobStorage**

```python
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
    def __init__(self, actual: int, limit: int):
        self.actual = actual
        self.limit = limit
        super().__init__(f"Blob size {actual} exceeds limit {limit}")


class BlobNotFoundError(Exception):
    pass


@dataclass(frozen=True)
class BlobPutResult:
    blob_hash: str
    byte_size: int
    mime_type: str
    temp_path: str  # caller decides whether to move or discard


class LocalBlobStorage:
    """Content-addressed local filesystem storage."""

    def __init__(self):
        self.base = Path(settings.LOCAL_STORAGE_PATH) / "blobs"
        self.base.mkdir(parents=True, exist_ok=True)

    def path_for(self, blob_hash: str) -> str:
        return str(self.base / blob_hash[:2] / blob_hash[2:4] / blob_hash)

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
        """Atomic rename temp file into content-addressed location."""
        final = self.path_for(blob_hash)
        os.makedirs(os.path.dirname(final), exist_ok=True)
        os.replace(temp_path, final)

    def exists(self, blob_hash: str) -> bool:
        return os.path.exists(self.path_for(blob_hash))

    async def get_bytes(self, blob_hash: str) -> bytes:
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
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    yield chunk

        return _iter()

    async def physical_delete(self, blob_hash: str) -> None:
        path = self.path_for(blob_hash)
        if os.path.exists(path):
            os.unlink(path)


class S3BlobStorage:
    """Content-addressed S3 storage."""

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

    def path_for(self, blob_hash: str) -> str:
        return f"blobs/{blob_hash[:2]}/{blob_hash[2:4]}/{blob_hash}"

    async def put_to_temp(self, data, *, claimed_mime_type, max_size, chunk_size=65536):
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
        pass  # S3 put_to_temp already uploads

    def exists(self, blob_hash: str) -> bool:
        try:
            self.client.head_object(Bucket=self.bucket, Key=self.path_for(blob_hash))
            return True
        except Exception:
            return False

    async def get_bytes(self, blob_hash: str) -> bytes:
        resp = self.client.get_object(Bucket=self.bucket, Key=self.path_for(blob_hash))
        return resp["Body"].read()

    async def open_stream(self, blob_hash: str):
        resp = self.client.get_object(Bucket=self.bucket, Key=self.path_for(blob_hash))
        def _iter():
            for chunk in resp["Body"].iter_chunks(65536):
                yield chunk
        return _iter()

    async def physical_delete(self, blob_hash: str) -> None:
        self.client.delete_object(Bucket=self.bucket, Key=self.path_for(blob_hash))

    def get_presigned_url(self, blob_hash: str, expires_in: int = 3600) -> str:
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
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/blob_storage.py
git commit -m "feat(storage): add content-addressed BlobStorage layer"
```

---

## Task 5: BlobService (DB + refcount layer)

**Files:**
- Create: `backend/app/services/blob_service.py`

- [ ] **Step 1: Write BlobService**

```python
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
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/blob_service.py
git commit -m "feat(storage): add BlobService with refcount management"
```

---

## Task 6: Delete old storage_service.py

**Files:**
- Delete: `backend/app/services/storage_service.py`

- [ ] **Step 1: Delete the file**

```bash
git rm backend/app/services/storage_service.py
```

- [ ] **Step 2: Commit**

```bash
git commit -m "refactor(storage): remove old path-based StorageService"
```

> **Note to implementer:** After this commit, imports of `storage_service` will break throughout the codebase. The following tasks fix each broken import one by one. This is intentional — it ensures we don't miss any usage.

---

## Task 7: Files router (URL serving)

**Files:**
- Create: `backend/app/api/v1/files.py`

- [ ] **Step 1: Write the files router**

```python
# backend/app/api/v1/files.py
"""
Business-path file serving router.
Mounted at top-level /files (not under /api/v1) for backwards URL compat.
Resolves blob_hash internally; never exposes hashes to clients.
"""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.db.session import get_db
from app.models.blob import Blob
from app.models.clothing_item import ClothingItem, Image, Model3D
from app.models.creator import (
    CardPack,
    CreatorItem,
    CreatorItemImage,
    CreatorItemModel3D,
)
from app.models.outfit_preview import (
    Outfit,
    OutfitPreviewTask,
    OutfitPreviewTaskItem,
)
from app.models.styled_generation import StyledGeneration
from app.services.blob_storage import get_blob_storage

router = APIRouter()
logger = logging.getLogger(__name__)

_blob_storage = None


def _storage():
    global _blob_storage
    if _blob_storage is None:
        _blob_storage = get_blob_storage()
    return _blob_storage


IMAGE_KIND_MAP = {
    "original-front": ("ORIGINAL_FRONT", None),
    "original-back": ("ORIGINAL_BACK", None),
    "processed-front": ("PROCESSED_FRONT", None),
    "processed-back": ("PROCESSED_BACK", None),
    "angle-0": ("ANGLE_VIEW", 0),
    "angle-45": ("ANGLE_VIEW", 45),
    "angle-90": ("ANGLE_VIEW", 90),
    "angle-135": ("ANGLE_VIEW", 135),
    "angle-180": ("ANGLE_VIEW", 180),
    "angle-225": ("ANGLE_VIEW", 225),
    "angle-270": ("ANGLE_VIEW", 270),
    "angle-315": ("ANGLE_VIEW", 315),
}


async def _stream_blob(db: Session, blob_hash: str):
    """Look up blob metadata and return a StreamingResponse."""
    blob = db.query(Blob).filter(Blob.blob_hash == blob_hash).first()
    if not blob:
        raise HTTPException(404, "File not found")
    storage = _storage()
    return StreamingResponse(
        await storage.open_stream(blob_hash),
        media_type=blob.mime_type,
    )


# ---- Clothing item files ----

@router.get("/clothing-items/{item_id}/{kind}")
async def get_clothing_file(
    item_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = db.query(ClothingItem).filter(
        ClothingItem.id == item_id,
        ClothingItem.user_id == user_id,
    ).first()
    if not item:
        raise HTTPException(404)

    if kind == "model":
        model = db.query(Model3D).filter_by(clothing_item_id=item_id).first()
        if not model:
            raise HTTPException(404)
        blob = db.query(Blob).filter_by(blob_hash=model.blob_hash).first()
        storage = _storage()
        return StreamingResponse(
            await storage.open_stream(model.blob_hash),
            media_type="model/gltf-binary",
            headers={"Content-Disposition": f'attachment; filename="{item_id}.glb"'},
        )

    if kind not in IMAGE_KIND_MAP:
        raise HTTPException(404, f"Unknown image kind: {kind}")

    image_type, angle = IMAGE_KIND_MAP[kind]
    img = db.query(Image).filter_by(
        clothing_item_id=item_id,
        image_type=image_type,
        angle=angle,
    ).first()
    if not img:
        raise HTTPException(404)
    return await _stream_blob(db, img.blob_hash)


# ---- Creator item files ----

@router.get("/creator-items/{item_id}/{kind}")
async def get_creator_item_file(
    item_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = db.query(CreatorItem).filter(
        CreatorItem.id == item_id,
        CreatorItem.creator_id == user_id,
    ).first()
    if not item:
        raise HTTPException(404)

    if kind == "model":
        model = db.query(CreatorItemModel3D).filter_by(
            creator_item_id=item_id
        ).first()
        if not model:
            raise HTTPException(404)
        storage = _storage()
        return StreamingResponse(
            await storage.open_stream(model.blob_hash),
            media_type="model/gltf-binary",
        )

    if kind not in IMAGE_KIND_MAP:
        raise HTTPException(404)
    image_type, angle = IMAGE_KIND_MAP[kind]
    img = db.query(CreatorItemImage).filter_by(
        creator_item_id=item_id,
        image_type=image_type,
        angle=angle,
    ).first()
    if not img:
        raise HTTPException(404)
    return await _stream_blob(db, img.blob_hash)


# ---- Styled generation files ----

STYLED_GEN_KIND_MAP = {
    "selfie-original": "selfie_original_blob_hash",
    "selfie-processed": "selfie_processed_blob_hash",
    "result": "result_image_blob_hash",
}

@router.get("/styled-generations/{gen_id}/{kind}")
async def get_styled_generation_file(
    gen_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    gen = db.query(StyledGeneration).filter(
        StyledGeneration.id == gen_id,
        StyledGeneration.user_id == user_id,
    ).first()
    if not gen:
        raise HTTPException(404)

    attr = STYLED_GEN_KIND_MAP.get(kind)
    if not attr:
        raise HTTPException(404)
    blob_hash = getattr(gen, attr)
    if not blob_hash:
        raise HTTPException(404)
    return await _stream_blob(db, blob_hash)


# ---- Card pack cover ----

@router.get("/card-packs/{pack_id}/cover")
async def get_card_pack_cover(
    pack_id: UUID,
    db: Session = Depends(get_db),
):
    pack = db.query(CardPack).filter(CardPack.id == pack_id).first()
    if not pack or not pack.cover_image_blob_hash:
        raise HTTPException(404)
    return await _stream_blob(db, pack.cover_image_blob_hash)


# ---- Outfit preview files ----

@router.get("/outfit-preview-tasks/{task_id}/{kind}")
async def get_outfit_preview_file(
    task_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    task = db.query(OutfitPreviewTask).filter(
        OutfitPreviewTask.id == task_id,
        OutfitPreviewTask.user_id == user_id,
    ).first()
    if not task:
        raise HTTPException(404)

    if kind == "person-image":
        return await _stream_blob(db, task.person_image_blob_hash)
    elif kind == "preview":
        if not task.preview_image_blob_hash:
            raise HTTPException(404)
        return await _stream_blob(db, task.preview_image_blob_hash)
    raise HTTPException(404)


@router.get("/outfits/{outfit_id}/preview")
async def get_outfit_preview(
    outfit_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    outfit = db.query(Outfit).filter(
        Outfit.id == outfit_id,
        Outfit.user_id == user_id,
    ).first()
    if not outfit:
        raise HTTPException(404)
    return await _stream_blob(db, outfit.preview_image_blob_hash)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/api/v1/files.py
git commit -m "feat(api): add /files business-path router for blob serving"
```

---

## Task 8: Import / un-import endpoints

**Files:**
- Create: `backend/app/schemas/imports.py`
- Create: `backend/app/api/v1/imports.py`

- [ ] **Step 1: Write import schemas**

```python
# backend/app/schemas/imports.py
from uuid import UUID
from pydantic import BaseModel


class ImportCardPackRequest(BaseModel):
    card_pack_id: UUID


class ImportCardPackResponse(BaseModel):
    cardPackId: str
    importedItemIds: list[str]
```

- [ ] **Step 2: Write import/un-import endpoints**

```python
# backend/app/api/v1/imports.py
"""Card pack import and un-import endpoints."""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.db.session import get_db
from app.models.card_pack_import import CardPackImport
from app.models.clothing_item import ClothingItem, Image, Model3D
from app.models.creator import CardPack, CardPackItem
from app.schemas.imports import ImportCardPackRequest, ImportCardPackResponse
from app.services.blob_service import get_blob_service

router = APIRouter(prefix="/imports", tags=["Imports"])
logger = logging.getLogger(__name__)


def _delete_clothing_item_internal(db: Session, item: ClothingItem) -> None:
    """
    Delete a clothing item and release all its blob refs.
    Shared between DELETE /clothing-items/:id and un-import.
    """
    blob_service = get_blob_service()
    blob_hashes = [img.blob_hash for img in item.images if img.blob_hash]
    if item.model_3d and item.model_3d.blob_hash:
        blob_hashes.append(item.model_3d.blob_hash)

    db.delete(item)
    db.flush()

    for h in blob_hashes:
        blob_service.release(db, h)


@router.post("/card-pack", status_code=201)
def import_card_pack(
    body: ImportCardPackRequest,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    pack = (
        db.query(CardPack)
        .filter(CardPack.id == body.card_pack_id, CardPack.status == "PUBLISHED")
        .first()
    )
    if not pack:
        raise HTTPException(404, "Pack not found or not published")

    existing = db.query(CardPackImport).filter_by(
        user_id=user_id, card_pack_id=pack.id,
    ).first()
    if existing:
        raise HTTPException(409, "Pack already imported")

    db.add(CardPackImport(user_id=user_id, card_pack_id=pack.id))

    blob_service = get_blob_service()
    imported_item_ids = []

    pack_items = (
        db.query(CardPackItem)
        .filter(CardPackItem.card_pack_id == pack.id)
        .order_by(CardPackItem.sort_order)
        .all()
    )

    for pi in pack_items:
        ci = pi.creator_item

        clothing_item = ClothingItem(
            user_id=user_id,
            source="IMPORTED",
            name=ci.name,
            description=ci.description,
            predicted_tags=list(ci.predicted_tags) if ci.predicted_tags else [],
            final_tags=list(ci.final_tags) if ci.final_tags else [],
            is_confirmed=True,
            custom_tags=[],
            imported_from_card_pack_id=pack.id,
            imported_from_creator_item_id=ci.id,
        )
        db.add(clothing_item)
        db.flush()

        for ci_img in ci.images:
            db.add(Image(
                clothing_item_id=clothing_item.id,
                image_type=ci_img.image_type,
                angle=ci_img.angle,
                blob_hash=ci_img.blob_hash,
            ))
            blob_service.addref(db, ci_img.blob_hash)

        if ci.model_3d:
            db.add(Model3D(
                clothing_item_id=clothing_item.id,
                model_format=ci.model_3d.model_format,
                blob_hash=ci.model_3d.blob_hash,
                vertex_count=ci.model_3d.vertex_count,
                face_count=ci.model_3d.face_count,
            ))
            blob_service.addref(db, ci.model_3d.blob_hash)

        imported_item_ids.append(str(clothing_item.id))

    pack.import_count = (pack.import_count or 0) + 1
    db.commit()

    return ImportCardPackResponse(
        cardPackId=str(pack.id),
        importedItemIds=imported_item_ids,
    )


@router.delete("/card-pack/{pack_id}", status_code=204)
def unimport_card_pack(
    pack_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    record = db.query(CardPackImport).filter_by(
        user_id=user_id, card_pack_id=pack_id,
    ).first()
    if not record:
        raise HTTPException(404, "Not imported")

    items = db.query(ClothingItem).filter(
        ClothingItem.user_id == user_id,
        ClothingItem.imported_from_card_pack_id == pack_id,
    ).all()

    for item in items:
        _delete_clothing_item_internal(db, item)

    db.delete(record)

    pack = db.query(CardPack).filter_by(id=pack_id).first()
    if pack and (pack.import_count or 0) > 0:
        pack.import_count -= 1

    db.commit()
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/schemas/imports.py backend/app/api/v1/imports.py
git commit -m "feat(api): add card pack import and un-import endpoints"
```

---

## Task 9: Wire main.py + router.py

**Files:**
- Modify: `backend/app/main.py`
- Modify: `backend/app/api/v1/router.py`

- [ ] **Step 1: Update main.py**

Remove the StaticFiles mount (lines 41-43):
```python
# DELETE these lines:
storage_dir = Path(settings.LOCAL_STORAGE_PATH)
storage_dir.mkdir(parents=True, exist_ok=True)
app.mount("/files", StaticFiles(directory=str(storage_dir)), name="files")
```

Remove the `StaticFiles` import.

Add the files router mount (after `app.include_router(api_router, ...)`):
```python
from app.api.v1 import files as files_router
app.include_router(files_router.router, prefix="/files", tags=["Files"])
```

Ensure the blobs directory is created at startup:
```python
from pathlib import Path
blobs_dir = Path(settings.LOCAL_STORAGE_PATH) / "blobs"
blobs_dir.mkdir(parents=True, exist_ok=True)
```

- [ ] **Step 2: Update router.py**

Add imports router:
```python
from app.api.v1 import imports
```

Add to router includes:
```python
api_router.include_router(imports.router)
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/main.py backend/app/api/v1/router.py
git commit -m "feat(wiring): mount /files router, add /imports to api_router, remove static mount"
```

---

## Task 10: Refactor clothing upload + pipeline + delete

**Files:**
- Modify: `backend/app/api/v1/clothing.py`
- Modify: `backend/app/services/clothing_pipeline.py`

- [ ] **Step 1: Refactor clothing.py — imports**

Replace:
```python
from app.services.storage_service import StorageService, get_storage_service
```
with:
```python
from app.services.blob_service import get_blob_service
from app.services.blob_storage import get_blob_storage
```

Remove `_storage()` helper. Replace all `storage = _storage()` with `blob_service = get_blob_service()`.

- [ ] **Step 2: Refactor clothing.py — POST create handler**

Replace the storage.upload calls in `create_clothing_item`:
```python
# OLD:
front_path = _storage_path(user_id, item.id, "original_front.jpg")
await storage.upload(_to_buffer(front_bytes), front_path)
db.add(Image(clothing_item_id=item.id, image_type="ORIGINAL_FRONT", storage_path=front_path))

# NEW:
blob_service = get_blob_service()
front_blob = await blob_service.ingest_upload(
    db, io.BytesIO(front_bytes),
    claimed_mime_type=front_image.content_type or "image/jpeg",
    max_size=settings.MAX_UPLOAD_SIZE_BYTES,
)
db.add(Image(
    clothing_item_id=item.id,
    image_type="ORIGINAL_FRONT",
    blob_hash=front_blob.blob_hash,
))
```

Same pattern for `back_image` if present.

- [ ] **Step 3: Refactor clothing.py — URL construction**

Replace `_build_image_set` to use business URLs:
```python
def _build_image_url(item_id: UUID, kind: str) -> str:
    return f"/files/clothing-items/{item_id}/{kind}"
```

In the response builder, use this instead of `storage.get_url(img.storage_path)`:
```python
"originalFrontUrl": _build_image_url(item_id, "original-front"),
"processedFrontUrl": _build_image_url(item_id, "processed-front"),
# etc.
```

- [ ] **Step 4: Add DELETE /clothing-items/:id**

Add new endpoint (see spec §6.3):
```python
from app.api.v1.imports import _delete_clothing_item_internal

@router.delete("/{item_id}", status_code=204)
def delete_clothing_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404, "Clothing item not found")

    active = db.query(ProcessingTask).filter(
        ProcessingTask.clothing_item_id == item_id,
        ProcessingTask.status.in_(["PENDING", "PROCESSING"]),
    ).first()
    if active:
        raise HTTPException(409, "Cannot delete while processing")

    _delete_clothing_item_internal(db, item)
    db.commit()
```

- [ ] **Step 5: Refactor clothing.py — model download**

Replace `download_model` handler:
```python
# OLD:
data = await storage.download(model.storage_path)
return Response(content=data, ...)

# NEW:
blob_storage = get_blob_storage()
data = await blob_storage.get_bytes(model.blob_hash)
return Response(content=data, media_type="model/gltf-binary", ...)
```

- [ ] **Step 6: Refactor clothing_pipeline.py**

Replace imports:
```python
# OLD:
from app.services.storage_service import StorageService, get_storage_service

# NEW:
from app.services.blob_service import get_blob_service
from app.services.blob_storage import get_blob_storage
```

Replace storage instance:
```python
# OLD:
storage = get_storage_service()

# NEW:
blob_service = get_blob_service()
blob_storage = get_blob_storage()
```

Replace all `storage.download()`:
```python
# OLD:
payload = await storage.download(img.storage_path)

# NEW:
payload = await blob_storage.get_bytes(img.blob_hash)
```

Replace all `storage.upload()` + Image creation:
```python
# OLD:
await storage.upload(io.BytesIO(front_proc), proc_front_path)
_upsert_image(db, item.id, "PROCESSED_FRONT", proc_front_path)

# NEW:
proc_blob = await blob_service.ingest_upload(
    db, io.BytesIO(front_proc),
    claimed_mime_type="image/png",
    max_size=settings.MAX_UPLOAD_SIZE_BYTES * 2,
)
_upsert_image(db, item.id, "PROCESSED_FRONT", proc_blob.blob_hash)
```

Update `_upsert_image` to use `blob_hash` parameter instead of `path`:
```python
def _upsert_image(db, clothing_id, image_type, blob_hash, angle=None):
    # ... query for existing
    if existing:
        existing.blob_hash = blob_hash
    else:
        db.add(Image(
            clothing_item_id=clothing_id,
            image_type=image_type,
            blob_hash=blob_hash,
            angle=angle,
        ))
```

Same for `_upsert_model`:
```python
def _upsert_model(db, clothing_id, *, blob_hash, vertex_count, face_count):
    # ... query for existing
    if existing:
        existing.blob_hash = blob_hash
        existing.vertex_count = vertex_count
        existing.face_count = face_count
    else:
        db.add(Model3D(
            clothing_item_id=clothing_id,
            model_format="glb",
            blob_hash=blob_hash,
            vertex_count=vertex_count,
            face_count=face_count,
        ))
```

Update `cleanup_pipeline_artifacts` to release blobs instead of calling `storage.delete()`:
```python
async def cleanup_pipeline_artifacts(db, clothing_id, *, commit=True):
    blob_service = get_blob_service()
    derived = db.query(Image).filter(
        Image.clothing_item_id == clothing_id,
        Image.image_type.in_(("PROCESSED_FRONT", "PROCESSED_BACK", "ANGLE_VIEW")),
    ).all()
    for img in derived:
        blob_service.release(db, img.blob_hash)
        db.delete(img)

    model = db.query(Model3D).filter_by(clothing_item_id=clothing_id).first()
    if model:
        blob_service.release(db, model.blob_hash)
        db.delete(model)

    if commit:
        db.commit()
```

- [ ] **Step 7: Commit**

```bash
git add backend/app/api/v1/clothing.py backend/app/services/clothing_pipeline.py
git commit -m "feat(clothing): refactor to CAS storage, add DELETE endpoint"
```

---

## Task 11: Refactor creator items + card packs

**Files:**
- Modify: `backend/app/api/v1/creator_items.py`
- Modify: `backend/app/api/v1/card_packs.py`
- Modify: `backend/app/services/creator_pipeline.py`

- [ ] **Step 1: Refactor creator_items.py**

Same pattern as clothing.py:
- Replace `from app.services.storage_service import ...` with blob imports
- Replace `storage.upload()` in POST handler with `blob_service.ingest_upload()`
- Replace `CreatorItemImage(storage_path=...)` with `CreatorItemImage(blob_hash=...)`
- Update URL construction to use `/files/creator-items/{id}/{kind}`
- Update DELETE handler to release blobs before deletion

- [ ] **Step 2: Refactor card_packs.py**

- Replace `cover_image_storage_path` references with `cover_image_blob_hash`
- Update URL construction for cover images to `/files/card-packs/{id}/cover`
- Update DELETE handler to:
  1. Check `CardPackImport` count (block if > 0)
  2. Release cover blob if present
  3. Only then delete the pack

- [ ] **Step 3: Refactor creator_pipeline.py**

Same pattern as clothing_pipeline.py: replace all `storage.upload()/download()` with blob_service/blob_storage calls.

- [ ] **Step 4: Commit**

```bash
git add backend/app/api/v1/creator_items.py backend/app/api/v1/card_packs.py \
       backend/app/services/creator_pipeline.py
git commit -m "feat(creator): refactor to CAS storage, update delete semantics"
```

---

## Task 12: Refactor styled generation + outfit preview

**Files:**
- Modify: `backend/app/api/v1/styled_generation.py`
- Modify: `backend/app/services/styled_generation_pipeline.py`
- Modify: `backend/app/api/v1/outfit_preview.py`
- Modify: `backend/app/services/outfit_preview_service.py`

- [ ] **Step 1: Refactor styled_generation.py API**

- Replace storage imports with blob imports
- POST handler: use `blob_service.ingest_upload()` for selfie image
- Update URL construction: `selfieOriginalUrl` becomes `/files/styled-generations/{id}/selfie-original` etc.
- DELETE handler: release selfie/processed/result blobs before deletion

- [ ] **Step 2: Refactor styled_generation_pipeline.py**

Replace all storage operations:
```python
# OLD: selfie download
selfie_original_bytes = await storage.download(gen.selfie_original_path)

# NEW:
selfie_original_bytes = await blob_storage.get_bytes(gen.selfie_original_blob_hash)

# OLD: processed selfie upload
await storage.upload(io.BytesIO(selfie_processed_bytes), processed_path)
gen.selfie_processed_path = processed_path

# NEW:
proc_blob = await blob_service.ingest_upload(
    db, io.BytesIO(selfie_processed_bytes),
    claimed_mime_type="image/png",
    max_size=settings.SELFIE_MAX_UPLOAD_SIZE_BYTES * 2,
)
gen.selfie_processed_blob_hash = proc_blob.blob_hash

# Same for result image upload
```

Also update the garment download:
```python
# OLD:
garment_bytes = await storage.download(processed_img.storage_path)

# NEW:
garment_bytes = await blob_storage.get_bytes(processed_img.blob_hash)
```

- [ ] **Step 3: Refactor outfit_preview.py API**

- Replace `storage.get_url(task.preview_image_path)` with `/files/outfit-preview-tasks/{task.id}/preview`
- Same for outfit preview URL

- [ ] **Step 4: Refactor outfit_preview_service.py**

Replace all storage operations:
```python
# OLD:
await storage.upload(io.BytesIO(person_bytes), person_image_path)

# NEW:
person_blob = await blob_service.ingest_upload(
    db, io.BytesIO(person_bytes),
    claimed_mime_type="image/png",
    max_size=settings.MAX_UPLOAD_SIZE_BYTES,
)
# Set task.person_image_blob_hash = person_blob.blob_hash
```

Same pattern for garment image uploads and result image storage.

- [ ] **Step 5: Commit**

```bash
git add backend/app/api/v1/styled_generation.py \
       backend/app/services/styled_generation_pipeline.py \
       backend/app/api/v1/outfit_preview.py \
       backend/app/services/outfit_preview_service.py
git commit -m "feat(styled-gen+outfit): refactor to CAS storage"
```

---

## Task 13: GC sweep + Celery Beat + Docker

**Files:**
- Modify: `backend/app/tasks.py`
- Modify: `backend/app/core/celery_app.py`
- Modify: `docker-compose.yml`

- [ ] **Step 1: Add gc_sweep task to tasks.py**

```python
from datetime import timedelta
from app.services.blob_storage import get_blob_storage

@celery_app.task(name="blobs.gc_sweep")
def gc_sweep() -> None:
    """Sweep blobs with ref_count=0 and pending_delete_at older than 24h."""
    from app.db.session import SessionLocal
    from app.models.blob import Blob
    from sqlalchemy import text

    db = SessionLocal()
    blob_storage = get_blob_storage()
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
        candidates = (
            db.query(Blob)
            .filter(
                Blob.pending_delete_at.isnot(None),
                Blob.pending_delete_at < cutoff,
                Blob.ref_count == 0,
            )
            .limit(1000)
            .all()
        )

        deleted_count = 0
        for candidate in candidates:
            try:
                db.execute(
                    text("SELECT pg_advisory_xact_lock(hashtext(:h))"),
                    {"h": candidate.blob_hash},
                )
                row = (
                    db.query(Blob)
                    .filter(
                        Blob.blob_hash == candidate.blob_hash,
                        Blob.ref_count == 0,
                        Blob.pending_delete_at < cutoff,
                    )
                    .first()
                )
                if row is None:
                    db.commit()
                    continue

                db.delete(row)
                db.flush()

                import asyncio
                try:
                    asyncio.run(blob_storage.physical_delete(candidate.blob_hash))
                except FileNotFoundError:
                    pass

                db.commit()
                deleted_count += 1
            except Exception:
                db.rollback()
                logger.exception("GC failed for %s", candidate.blob_hash)

        if deleted_count:
            logger.info("GC swept %d orphaned blobs", deleted_count)
    finally:
        db.close()
```

- [ ] **Step 2: Add beat_schedule to celery_app.py**

Add at the end of the file:
```python
from celery.schedules import crontab

celery_app.conf.beat_schedule = {
    "blob-gc-sweep": {
        "task": "blobs.gc_sweep",
        "schedule": crontab(minute=17),
    },
}
```

- [ ] **Step 3: Add celery-beat service to docker-compose.yml**

Add after the `celery-styled-gen` service:
```yaml
  celery-beat:
    build:
      context: ./backend
      dockerfile: Dockerfile
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      POSTGRES_SERVER: db
      POSTGRES_USER: wardrobe_user
      POSTGRES_PASSWORD: wardrobe_pass
      POSTGRES_DB: wardrobe_db
      POSTGRES_PORT: 5432
      REDIS_URL: redis://redis:6379/0
      LOCAL_STORAGE_PATH: /app/storage
      PYTHONPATH: /app
    command: >
      celery -A app.core.celery_app beat
      --loglevel=info
    volumes:
      - backend_storage:/app/storage
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/tasks.py backend/app/core/celery_app.py docker-compose.yml
git commit -m "feat(gc): add blob GC sweep task with celery beat"
```

---

## Task 14: Reconciliation script + final cleanup

**Files:**
- Create: `backend/scripts/verify_blob_refcount.py`

- [ ] **Step 1: Write reconciliation script**

```python
#!/usr/bin/env python3
"""
Verify blob refcounts match actual references across all business tables.
Run: cd backend && python -m scripts.verify_blob_refcount

Does NOT auto-correct. Reports discrepancies for manual diagnosis.
"""

import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.models.blob import Blob  # noqa: E402
from sqlalchemy import text  # noqa: E402

REFERENCING_TABLES = [
    ("images", "blob_hash"),
    ("creator_item_images", "blob_hash"),
    ("models_3d", "blob_hash"),
    ("creator_models_3d", "blob_hash"),
    ("styled_generations", "selfie_original_blob_hash"),
    ("styled_generations", "selfie_processed_blob_hash"),
    ("styled_generations", "result_image_blob_hash"),
    ("outfit_preview_tasks", "person_image_blob_hash"),
    ("outfit_preview_tasks", "preview_image_blob_hash"),
    ("outfit_preview_task_items", "garment_image_blob_hash"),
    ("outfits", "preview_image_blob_hash"),
    ("card_packs", "cover_image_blob_hash"),
]


def main():
    db = SessionLocal()
    try:
        actual_counts: Counter = Counter()

        for table, column in REFERENCING_TABLES:
            rows = db.execute(
                text(f"SELECT {column} FROM {table} WHERE {column} IS NOT NULL")
            ).fetchall()
            for (blob_hash,) in rows:
                actual_counts[blob_hash] += 1

        blobs = db.query(Blob).all()
        issues = 0

        for blob in blobs:
            actual = actual_counts.get(blob.blob_hash, 0)
            if actual != blob.ref_count:
                print(
                    f"MISMATCH: blob={blob.blob_hash[:16]}... "
                    f"recorded={blob.ref_count} actual={actual}"
                )
                issues += 1

        for h, count in actual_counts.items():
            if not db.query(Blob).filter_by(blob_hash=h).first():
                print(f"ORPHAN REF: {h[:16]}... referenced {count}x but no blob row")
                issues += 1

        if issues == 0:
            print(f"OK: all {len(blobs)} blobs have correct refcounts")
        else:
            print(f"FOUND {issues} issue(s)")
            sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Commit**

```bash
git add backend/scripts/verify_blob_refcount.py
git commit -m "ops: add blob refcount reconciliation script"
```

---

## Task 15: Verification

- [ ] **Step 1: Wipe dev data**

```bash
docker compose down -v
```

- [ ] **Step 2: Rebuild and start**

```bash
docker compose up --build
```

Expected: all migrations run, demo user created, all services healthy.

- [ ] **Step 3: Verify single head**

```bash
cd backend && alembic heads
```

Expected output: `20260415_000010 (head)`

- [ ] **Step 4: Test upload flow**

```bash
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo123456"}' | python -c "import sys,json;print(json.load(sys.stdin)['data']['token'])")

curl -X POST http://localhost:8000/api/v1/clothing-items \
  -H "Authorization: Bearer $TOKEN" \
  -F "front_image=@test_image.jpg"
```

Expected: 202 response with item ID. After pipeline completes, `GET /files/clothing-items/{id}/processed-front` returns bytes.

- [ ] **Step 5: Test delete flow**

```bash
curl -X DELETE http://localhost:8000/api/v1/clothing-items/{id} \
  -H "Authorization: Bearer $TOKEN"
```

Expected: 204. Item gone from DB. Blob refcount decremented.

- [ ] **Step 6: Run reconciliation**

```bash
cd backend && python -m scripts.verify_blob_refcount
```

Expected: `OK: all N blobs have correct refcounts`

- [ ] **Step 7: Final commit with any fixes**

If verification exposed issues, fix them and commit. Then tag the branch as implementation-complete.

---

## Execution notes

- **Import order matters**: Tasks 1-5 are foundation. Task 6 (delete old storage_service) intentionally breaks the build. Tasks 7-12 fix the broken imports one by one.
- **Each task produces a commit** so progress is checkpointable.
- **After Task 6**, the app will not start. Only after Tasks 7-12 are all complete will the app be functional again.
- **Alternative sequencing**: if you prefer the app to remain functional between commits, you can defer Task 6 (delete storage_service.py) until after Tasks 7-12, and instead have Tasks 7-12 import from both old and new services during transition.
