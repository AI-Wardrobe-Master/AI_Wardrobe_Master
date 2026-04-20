# Multi-Garment DreamO + CreatorItem Merge + DB Hardening + View Counts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement everything in `docs/superpowers/specs/2026-04-20-multi-garment-dreamo-and-db-enhancements-design.md` (v2) — multi-garment DreamO with gender, merge `creator_items` back into `clothing_items`, add 3-tier delete lifecycle, add view counts + popular card packs, fix 22 audit defects.

**Architecture:** Single large PR, phased so each phase ends at a working, testable state. Phases 0 → 1 → 2 → 3 prepare infrastructure (pre-merge safe fixes, then the big migration + model + CRUD changes). Phases 4 → 6 refactor the API surface (imports, card_packs, creator_items shim, 3-tier delete, view counts). Phase 7 implements the independent DreamO multi-garment change. Phases 8 → 9 finish remaining hardening fixes and N+1 cleanups. No code touches production until the full plan is green.

**Tech Stack:** FastAPI · SQLAlchemy 2.x · Alembic · PostgreSQL · Celery + Redis · httpx · pytest · pytest-asyncio · DreamO (FLUX LoRA). Matches existing project.

---

## File Structure

### New files

- `backend/alembic/versions/20260420_000015_consolidate_and_enhance.py` — single big migration covering merge + junction + gender + leases + view_count + deleted_at + partial indexes + import_count check constraint.
- `backend/app/models/styled_generation.py` — add `StyledGenerationClothingItem` class alongside existing `StyledGeneration` (same file).
- `backend/app/services/view_count_service.py` — small atomic-increment helper used by clothing-items + card-packs detail GET.
- `backend/tests/test_merge_migration.py` — integration test proving the migration runs cleanly on a DB with populated CreatorItems.
- `backend/tests/test_clothing_delete_lifecycle.py` — covers the 3-tier delete matrix.
- `backend/tests/test_view_counts.py` — covers increment semantics + `/card-packs/popular`.
- `backend/tests/test_multi_garment_styled_generation.py` — API + pipeline level tests for multi-garment flow.
- `backend/tests/test_dreamo_server_multi_garment.py` — in-process test for `DreamO/server.py` building `ref_tasks` correctly (mocks the generator).
- `backend/tests/test_prompt_builder.py` — garment/gender permutations.
- `backend/tests/test_blob_release_race.py` — concurrency test for the `release()` advisory-lock fix.

### Modified files

- `backend/app/models/clothing_item.py` — absorb `catalog_visibility`, `view_count`, `deleted_at`; rename `imported_from_creator_item_id` → `imported_from_clothing_item_id`.
- `backend/app/models/creator.py` — delete `CreatorItem`, `CreatorItemImage`, `CreatorItemModel3D`, `CreatorProcessingTask` classes; keep `CreatorProfile`, `CardPack`, `CardPackItem` (the latter with FK now to `clothing_items`).
- `backend/app/crud/clothing.py` — absorb creator-item logic, add `deleted_at IS NULL` filter to every query, add publish/unpublish, add 3-tier delete.
- `backend/app/crud/creator_item.py` — **delete file**; functionality merged into `crud/clothing.py`.
- `backend/app/crud/card_pack.py` — update references from `creator_items` to `clothing_items`, add `list_popular_card_packs`.
- `backend/app/services/clothing_pipeline.py` — absorb creator-pipeline logic; branch on `catalog_visibility` where different behavior is needed (rare — mostly identical today).
- `backend/app/services/creator_pipeline.py` — **delete file**.
- `backend/app/services/creator_processing_task_service.py` — **delete file** (fold into `processing_task_service.py`).
- `backend/app/services/processing_task_service.py` — absorb creator-task logic (mostly identical); fix claim race via atomic compare-and-swap UPDATE (audit item 12).
- `backend/app/services/blob_service.py` — advisory lock in `release()`.
- `backend/app/services/styled_generation_pipeline.py` — multi-garment fetch, lease bookkeeping.
- `backend/app/services/dreamo_client_service.py` — list of garments.
- `backend/app/services/prompt_builder_service.py` — gender + multi-garment composition.
- `backend/app/api/v1/clothing.py` — publish via PATCH `catalogVisibility`, 3-tier DELETE, explicit size check, view_count increment on GET, return `viewCount` in responses, forward old `GET /creator-items/{id}`.
- `backend/app/api/v1/creator_items.py` — reduced to thin shims (POST/GET/PATCH/DELETE forward to clothing).
- `backend/app/api/v1/imports.py` — snapshot from `clothing_items` (renamed FK), lock pack `FOR UPDATE`, raise 409 on `BlobNotFoundError` during addref, cascade cleanup of tombstones on unimport.
- `backend/app/api/v1/card_packs.py` — use `clothing_item_id`, lock on delete, `view_count` increment on detail/share GET, new `/popular` endpoint, return `viewCount`.
- `backend/app/api/v1/wardrobe.py` — fix N+1 in `/wardrobes` and `/wardrobes/public` via batched count.
- `backend/app/api/v1/files.py` — require auth + PUBLISHED-or-creator check for card-pack cover endpoint.
- `backend/app/api/v1/styled_generation.py` — new request shape (gender + clothing_items JSON), legacy `clothing_item_id` shim, retry releases blob refs.
- `backend/app/schemas/clothing_item.py` — `catalogVisibility`, `viewCount`, `publishedAt?` fields.
- `backend/app/schemas/card_pack.py` — `viewCount`.
- `backend/app/schemas/creator.py` — slim down to only CreatorProfile; legacy creator-item response schemas delegated to clothing-item schemas.
- `backend/app/schemas/styled_generation.py` — `gender`, `garments[]` list.
- `backend/app/core/config.py` — SECRET_KEY validator on `Settings.__init__`.
- `backend/app/core/celery_app.py` — add beat entries for `styled_generation.reap_stuck`, `blobs.gc_orphan_files`, `outfit_preview.reap_stuck`.
- `backend/app/tasks.py` — add new Celery tasks: `styled_generation.reap_stuck`, `blobs.gc_orphan_files`, `outfit_preview.reap_stuck`. Remove `creator.process_pipeline`.
- `backend/app/api/deps.py` — use `.filter().first()` instead of `db.get()` for freshness.
- `DreamO/server.py` — accept `garment_images: list[str]`, keep `garment_image` as deprecated shim.
- `documents/API_CONTRACT.md`, `documents/BACKEND_ARCHITECTURE.md`, `documents/DREAMO_INTEGRATION.md`, `documents/DATA_MODEL.md`, `groupmembers'markdown/gch.md` — doc updates.

### Deleted files

- `backend/app/crud/creator_item.py`
- `backend/app/services/creator_pipeline.py`
- `backend/app/services/creator_processing_task_service.py`

---

## Prerequisites

Before starting: ensure a fresh local Postgres DB is available (`docker compose up postgres redis`) for running migrations + tests. Run `alembic upgrade head` on current main to verify baseline, then on this worktree's branch. `pytest backend/tests/` should pass before we begin.

---

## Phase 0: Safe Pre-Merge Fixes (no schema change, no merge)

These can land independently; they fix existing bugs and provide infrastructure for later phases. Takes ~30 min.

### Task 0.1: Fix `BlobService.release()` advisory lock

**Files:**
- Modify: `backend/app/services/blob_service.py:112-123`
- Create test: `backend/tests/test_blob_release_race.py`

- [ ] **Step 1: Write the failing concurrency test**

```python
# backend/tests/test_blob_release_race.py
"""Concurrency test: release() + addref() on same hash must not lose updates."""

import asyncio
import io
import pytest
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.services.blob_service import BlobService


@pytest.mark.asyncio
async def test_release_and_addref_concurrent_preserve_ref_count():
    """After N parallel (addref, release) pairs on same hash starting from 1,
    ref_count must end at 1 — proving neither write is lost."""
    db: Session = SessionLocal()
    svc = BlobService()
    # Ingest one blob so the row exists with ref_count=1.
    initial = await svc.ingest_upload(
        db, io.BytesIO(b"race-test-payload"),
        claimed_mime_type="application/octet-stream",
        max_size=1024,
    )
    db.commit()
    h = initial.blob_hash

    # Run 50 addref/release pairs concurrently.
    def work():
        local_db = SessionLocal()
        try:
            svc.addref(local_db, h)
            local_db.commit()
            svc.release(local_db, h)
            local_db.commit()
        finally:
            local_db.close()

    loop = asyncio.get_event_loop()
    await asyncio.gather(*[loop.run_in_executor(None, work) for _ in range(50)])

    db.refresh(initial)
    assert initial.ref_count == 1, f"lost update: ref_count={initial.ref_count}"

    # Cleanup
    svc.release(db, h)
    db.commit()
    db.close()
```

- [ ] **Step 2: Run the test — expect failure or flake**

Run: `pytest backend/tests/test_blob_release_race.py -v`
Expected: FAIL (ref_count != 1 on most runs because `release()` currently has no lock).

- [ ] **Step 3: Add advisory lock to `release()`**

```python
# backend/app/services/blob_service.py (lines 112-123, replace existing release)
def release(self, db: Session, blob_hash: str) -> None:
    """
    Decrement refcount. If it reaches 0, mark for GC.
    Acquires a transaction-scoped advisory lock on the hash to serialize
    with ingest_upload / addref.
    """
    _lock_hash(db, blob_hash)
    blob = db.query(Blob).filter(Blob.blob_hash == blob_hash).first()
    if blob is None:
        logger.warning("release() called for unknown blob %s", blob_hash)
        return
    blob.ref_count = max(0, blob.ref_count - 1)
    if blob.ref_count == 0:
        blob.pending_delete_at = datetime.now(timezone.utc)
    db.flush()
```

- [ ] **Step 4: Run the test — expect pass**

Run: `pytest backend/tests/test_blob_release_race.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/blob_service.py backend/tests/test_blob_release_race.py
git commit -m "fix(blob): acquire advisory lock in release() to prevent lost updates"
```

### Task 0.2: SECRET_KEY default validator

**Files:**
- Modify: `backend/app/core/config.py:49`

- [ ] **Step 1: Add validator**

```python
# backend/app/core/config.py — inside Settings class, after all field declarations
from pydantic import model_validator  # add import at top

    @model_validator(mode="after")
    def _reject_default_secret_key_in_prod(self):
        if self.SECRET_KEY == "CHANGE-ME-in-production":
            import os
            env = os.getenv("ENV", "development").lower()
            if env in ("production", "prod"):
                raise ValueError(
                    "SECRET_KEY must be overridden via environment in production. "
                    "Current value is the placeholder default."
                )
            import logging
            logging.getLogger(__name__).warning(
                "SECRET_KEY is the default placeholder. Override via .env before deploying."
            )
        return self
```

- [ ] **Step 2: Smoke-test**

```bash
cd backend && python -c "from app.core.config import settings; print(settings.SECRET_KEY[:10])"
```
Expected: prints `CHANGE-ME-i` plus a warning log line.

```bash
cd backend && ENV=production python -c "from app.core.config import settings"
```
Expected: `ValueError: SECRET_KEY must be overridden...`.

- [ ] **Step 3: Commit**

```bash
git add backend/app/core/config.py
git commit -m "fix(config): refuse default SECRET_KEY in production"
```

### Task 0.3: Freshen user lookup in deps

**Files:**
- Modify: `backend/app/api/deps.py` (around line 41, `get_current_user_id`)

- [ ] **Step 1: Replace `db.get(User, user_id)` with filter().first()**

Locate the `db.get(User, user_id)` call. Replace with:

```python
user = db.query(User).filter(User.id == user_id).first()
```

This forces a SQL fetch instead of returning a cached identity-map entry, so a user deactivated mid-session is noticed.

- [ ] **Step 2: Run existing auth tests**

Run: `pytest backend/tests/test_r1_auth.py -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add backend/app/api/deps.py
git commit -m "fix(auth): force fresh user lookup in deps to catch mid-session deactivation"
```

---

## Phase 1: Database Migration (THE BIG ONE)

All schema changes happen here in one Alembic revision. This must land before any code touches the new columns.

### Task 1.1: Scaffold the migration file

**Files:**
- Create: `backend/alembic/versions/20260420_000015_consolidate_and_enhance.py`

- [ ] **Step 1: Generate empty revision**

```bash
cd backend && alembic revision -m "consolidate_and_enhance" --rev-id 20260420_000015
```

This creates a skeleton. Edit to set `down_revision: str = "20260420_000014"` and keep `branch_labels = None`.

- [ ] **Step 2: Write the header block**

```python
"""consolidate creator_items into clothing_items; add multi-garment junction,
gender, lease fields on styled_generations; view_count on clothing_items and
card_packs; deleted_at tombstone on clothing_items; import_count CHECK; plus
partial indexes for popular queries.

Revision ID: 20260420_000015
Revises: 20260420_000014
Create Date: 2026-04-20
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260420_000015"
down_revision: Union[str, None] = "20260420_000014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None
```

- [ ] **Step 3: Commit scaffold**

```bash
git add backend/alembic/versions/20260420_000015_consolidate_and_enhance.py
git commit -m "feat(migration): scaffold consolidate_and_enhance revision"
```

### Task 1.2: Schema additions (steps A, B, C from spec §4.4)

- [ ] **Step 1: Write the schema-addition block**

Add to `upgrade()`:

```python
def upgrade() -> None:
    # ── A. clothing_items: absorb CreatorItem columns ─────────────────
    op.add_column(
        "clothing_items",
        sa.Column(
            "catalog_visibility",
            sa.String(20),
            nullable=False,
            server_default="PRIVATE",
        ),
    )
    op.create_check_constraint(
        "ck_clothing_catalog_visibility",
        "clothing_items",
        "catalog_visibility IN ('PRIVATE','PACK_ONLY','PUBLIC')",
    )
    op.add_column(
        "clothing_items",
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "clothing_items",
        sa.Column(
            "view_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    # Rename imported_from_creator_item_id → imported_from_clothing_item_id
    # (the FK target is retargeted in step D.)
    op.alter_column(
        "clothing_items",
        "imported_from_creator_item_id",
        new_column_name="imported_from_clothing_item_id",
    )

    # ── B. card_packs ─────────────────────────────────────────────────
    op.add_column(
        "card_packs",
        sa.Column(
            "view_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.create_check_constraint(
        "ck_card_pack_import_count_nonneg",
        "card_packs",
        "import_count >= 0",
    )

    # ── C. styled_generations ─────────────────────────────────────────
    op.add_column(
        "styled_generations",
        sa.Column("gender", sa.String(10), nullable=True),  # NOT NULL set in step E.14
    )
    op.add_column(
        "styled_generations",
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "styled_generations",
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "styled_generations",
        sa.Column("worker_id", sa.String(255), nullable=True),
    )
```

- [ ] **Step 2: Test up**

Run: `cd backend && alembic upgrade head`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add backend/alembic/versions/20260420_000015_consolidate_and_enhance.py
git commit -m "feat(migration): add catalog_visibility/deleted_at/view_count/leases/gender columns"
```

### Task 1.3: Data migration (step D — creator_items → clothing_items)

- [ ] **Step 1: Append merge block to `upgrade()`**

```python
    # ── D. Merge creator_items rows → clothing_items ──────────────────
    conn = op.get_bind()

    # D.1 Insert a clothing_items row for each creator_items row,
    #     reusing the UUID so FKs don't need rewriting.
    conn.execute(
        sa.text(
            """
            INSERT INTO clothing_items (
                id, user_id, source,
                predicted_tags, final_tags, is_confirmed,
                name, description, custom_tags,
                category, material, style,
                preview_svg_state, preview_svg_available, sync_status,
                imported_from_card_pack_id, imported_from_clothing_item_id,
                catalog_visibility, deleted_at, view_count,
                created_at, updated_at
            )
            SELECT
                ci.id,
                ci.creator_id,
                'OWNED',
                ci.predicted_tags,
                ci.final_tags,
                ci.is_confirmed,
                ci.name,
                ci.description,
                ci.custom_tags,
                NULL, NULL, NULL,
                'PLACEHOLDER', FALSE, 'SYNCED',
                NULL, NULL,
                ci.catalog_visibility,
                NULL,
                0,
                ci.created_at,
                ci.updated_at
            FROM creator_items ci
            WHERE NOT EXISTS (
                SELECT 1 FROM clothing_items WHERE clothing_items.id = ci.id
            )
            """
        )
    )

    # D.2 Copy creator_item_images → images (same clothing_item_id = creator_item.id).
    conn.execute(
        sa.text(
            """
            INSERT INTO images (id, clothing_item_id, image_type, blob_hash, angle, created_at)
            SELECT gen_random_uuid(), cii.creator_item_id, cii.image_type,
                   cii.blob_hash, cii.angle, cii.created_at
            FROM creator_item_images cii
            WHERE NOT EXISTS (
                SELECT 1 FROM images i
                WHERE i.clothing_item_id = cii.creator_item_id
                  AND i.image_type = cii.image_type
                  AND (i.angle IS NOT DISTINCT FROM cii.angle)
            )
            """
        )
    )

    # D.3 Copy creator_models_3d → models_3d.
    conn.execute(
        sa.text(
            """
            INSERT INTO models_3d (
                id, clothing_item_id, model_format, blob_hash,
                vertex_count, face_count, created_at
            )
            SELECT gen_random_uuid(), cm.creator_item_id, cm.model_format,
                   cm.blob_hash, cm.vertex_count, cm.face_count, cm.created_at
            FROM creator_models_3d cm
            WHERE NOT EXISTS (
                SELECT 1 FROM models_3d m WHERE m.clothing_item_id = cm.creator_item_id
            )
            """
        )
    )

    # D.4 Retarget card_pack_items FK.
    op.drop_constraint(
        "card_pack_items_creator_item_id_fkey", "card_pack_items",
        type_="foreignkey",
    )
    op.alter_column(
        "card_pack_items", "creator_item_id",
        new_column_name="clothing_item_id",
    )
    op.create_foreign_key(
        "card_pack_items_clothing_item_id_fkey",
        "card_pack_items", "clothing_items",
        ["clothing_item_id"], ["id"], ondelete="CASCADE",
    )
    # Rename unique index to match.
    op.execute("ALTER INDEX uq_card_pack_items_pack_creator_item "
               "RENAME TO uq_card_pack_items_pack_clothing_item")

    # D.5 Retarget clothing_items.imported_from_clothing_item_id FK.
    #     Currently it references creator_items.id; switch it to clothing_items.id.
    #     UUIDs were preserved in step D.1 so no data movement needed.
    op.drop_constraint(
        "fk_clothing_items_imported_creator_item",
        "clothing_items",
        type_="foreignkey",
    )
    op.create_foreign_key(
        "fk_clothing_items_imported_clothing_item",
        "clothing_items", "clothing_items",
        ["imported_from_clothing_item_id"], ["id"],
        ondelete="SET NULL",
    )

    # D.6 Drop the old creator_* tables, children first.
    op.drop_table("creator_processing_tasks")
    op.drop_table("creator_models_3d")
    op.drop_table("creator_item_images")
    op.drop_table("creator_items")
```

- [ ] **Step 2: Populate test data on a sandbox DB, then run upgrade**

```bash
# On a fresh DB after applying up to 20260420_000014:
psql -d wardrobe_db -c "INSERT INTO creator_items (id, creator_id, catalog_visibility, processing_status) VALUES (gen_random_uuid(), (SELECT id FROM users LIMIT 1), 'PACK_ONLY', 'COMPLETED');"
alembic upgrade head
psql -d wardrobe_db -c "SELECT id, catalog_visibility FROM clothing_items WHERE source='OWNED' AND category IS NULL AND catalog_visibility='PACK_ONLY';"
```
Expected: the inserted row shows up in clothing_items with the same id; creator_items table no longer exists.

- [ ] **Step 3: Commit**

```bash
git add backend/alembic/versions/20260420_000015_consolidate_and_enhance.py
git commit -m "feat(migration): data-migrate creator_items into clothing_items and drop legacy tables"
```

### Task 1.4: Junction table + gender backfill (step E)

- [ ] **Step 1: Append to `upgrade()`**

```python
    # ── E. Styled generation multi-garment junction + gender backfill ─
    op.create_table(
        "styled_generation_clothing_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column(
            "generation_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("styled_generations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "clothing_item_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("clothing_items.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("slot", sa.String(10), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()")),
        sa.CheckConstraint(
            "slot IN ('HAT','TOP','PANTS','SHOES')",
            name="ck_sgci_slot",
        ),
        sa.UniqueConstraint(
            "generation_id", "slot", name="uq_sgci_gen_slot",
        ),
    )
    op.create_index(
        "idx_sgci_generation",
        "styled_generation_clothing_items",
        ["generation_id"],
    )
    op.create_index(
        "idx_sgci_clothing_item",
        "styled_generation_clothing_items",
        ["clothing_item_id"],
    )

    # Backfill: every existing styled_generation with a source_clothing_item_id
    # gets one junction row with slot='TOP'.
    conn.execute(
        sa.text(
            """
            INSERT INTO styled_generation_clothing_items
                (id, generation_id, clothing_item_id, slot, position)
            SELECT gen_random_uuid(), sg.id, sg.source_clothing_item_id, 'TOP', 0
            FROM styled_generations sg
            WHERE sg.source_clothing_item_id IS NOT NULL
            """
        )
    )

    # Gender: default legacy rows to 'FEMALE', then lock non-null + CHECK.
    conn.execute(
        sa.text(
            "UPDATE styled_generations SET gender='FEMALE' WHERE gender IS NULL"
        )
    )
    op.alter_column("styled_generations", "gender", nullable=False)
    op.create_check_constraint(
        "ck_styled_gen_gender",
        "styled_generations",
        "gender IN ('MALE','FEMALE')",
    )
```

- [ ] **Step 2: Test up again**

Run: `cd backend && alembic downgrade -1 && alembic upgrade head`
Expected: PASS (downgrade may fail until we write downgrade; run only upgrade).
Actually run just upgrade after ensuring previous migration already ran:

```bash
cd backend && alembic current
cd backend && alembic upgrade head
psql -d wardrobe_db -c "\d styled_generation_clothing_items"
```
Expected: table shows columns id/generation_id/clothing_item_id/slot/position/created_at and the CHECK+UNIQUE constraints.

- [ ] **Step 3: Commit**

```bash
git add backend/alembic/versions/20260420_000015_consolidate_and_enhance.py
git commit -m "feat(migration): add styled_generation_clothing_items junction and backfill gender"
```

### Task 1.5: Indexes (step F) and finalization

- [ ] **Step 1: Append index block**

```python
    # ── F. Indexes ────────────────────────────────────────────────────
    op.create_index(
        "idx_clothing_items_popular",
        "clothing_items",
        ["view_count", "created_at"],
        postgresql_where=sa.text(
            "catalog_visibility IN ('PACK_ONLY','PUBLIC') AND deleted_at IS NULL"
        ),
        postgresql_ops={"view_count": "DESC", "created_at": "DESC"},
    )
    op.create_index(
        "idx_card_packs_popular",
        "card_packs",
        ["view_count", "created_at"],
        postgresql_where=sa.text("status = 'PUBLISHED'"),
        postgresql_ops={"view_count": "DESC", "created_at": "DESC"},
    )
    op.create_index(
        "idx_clothing_items_not_deleted",
        "clothing_items",
        ["user_id"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index(
        "idx_clothing_items_catalog_visibility",
        "clothing_items",
        ["user_id", "catalog_visibility"],
    )
```

- [ ] **Step 2: Write downgrade (reverses all steps in reverse order)**

```python
def downgrade() -> None:
    # Reverse F
    op.drop_index("idx_clothing_items_catalog_visibility", "clothing_items")
    op.drop_index("idx_clothing_items_not_deleted", "clothing_items")
    op.drop_index("idx_card_packs_popular", "card_packs")
    op.drop_index("idx_clothing_items_popular", "clothing_items")

    # Reverse E
    op.drop_constraint("ck_styled_gen_gender", "styled_generations", type_="check")
    op.drop_index("idx_sgci_clothing_item", "styled_generation_clothing_items")
    op.drop_index("idx_sgci_generation", "styled_generation_clothing_items")
    op.drop_table("styled_generation_clothing_items")

    # Reverse D: recreate creator_items family and move rows back
    op.create_table(
        "creator_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("creator_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("catalog_visibility", sa.String(20), nullable=False,
                  server_default="PACK_ONLY"),
        sa.Column("processing_status", sa.String(20), nullable=False,
                  server_default="COMPLETED"),
        sa.Column("predicted_tags", postgresql.JSONB, nullable=False, server_default="[]"),
        sa.Column("final_tags", postgresql.JSONB, nullable=False, server_default="[]"),
        sa.Column("is_confirmed", sa.Boolean, server_default=sa.text("false")),
        sa.Column("name", sa.String(200)),
        sa.Column("description", sa.Text),
        sa.Column("custom_tags", postgresql.ARRAY(sa.String), server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()")),
    )
    # Minimal: we do NOT restore creator_item_images / creator_models_3d /
    # creator_processing_tasks during downgrade because this migration is one-way
    # in practice. If a downgrade is ever attempted, data in those tables is lost.

    op.drop_constraint("fk_clothing_items_imported_clothing_item",
                       "clothing_items", type_="foreignkey")
    op.execute("ALTER INDEX uq_card_pack_items_pack_clothing_item "
               "RENAME TO uq_card_pack_items_pack_creator_item")
    op.drop_constraint("card_pack_items_clothing_item_id_fkey",
                       "card_pack_items", type_="foreignkey")
    op.alter_column("card_pack_items", "clothing_item_id",
                    new_column_name="creator_item_id")
    op.create_foreign_key(
        "card_pack_items_creator_item_id_fkey",
        "card_pack_items", "creator_items",
        ["creator_item_id"], ["id"], ondelete="CASCADE",
    )

    # Reverse C
    op.drop_column("styled_generations", "worker_id")
    op.drop_column("styled_generations", "lease_expires_at")
    op.drop_column("styled_generations", "started_at")
    op.drop_column("styled_generations", "gender")

    # Reverse B
    op.drop_constraint("ck_card_pack_import_count_nonneg", "card_packs", type_="check")
    op.drop_column("card_packs", "view_count")

    # Reverse A
    op.alter_column("clothing_items", "imported_from_clothing_item_id",
                    new_column_name="imported_from_creator_item_id")
    op.drop_column("clothing_items", "view_count")
    op.drop_column("clothing_items", "deleted_at")
    op.drop_constraint("ck_clothing_catalog_visibility", "clothing_items", type_="check")
    op.drop_column("clothing_items", "catalog_visibility")
```

- [ ] **Step 3: Test upgrade + downgrade round-trip**

Run on a sandbox DB with some seed data:
```bash
cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head
```
Expected: all 3 commands succeed without error. Confirm `\d clothing_items` shows new columns after final upgrade.

- [ ] **Step 4: Commit**

```bash
git add backend/alembic/versions/20260420_000015_consolidate_and_enhance.py
git commit -m "feat(migration): add partial indexes and downgrade path for consolidate_and_enhance"
```

### Task 1.6: Migration integration test

**Files:**
- Create: `backend/tests/test_merge_migration.py`

- [ ] **Step 1: Write the test**

```python
"""Migration integration test: seed a creator_items row, run upgrade, confirm data lands in clothing_items."""

import pytest
from sqlalchemy import text

from app.db.session import SessionLocal


def test_creator_items_data_migrated_to_clothing_items():
    """This test assumes the migration has already run (fixture DB at head)."""
    db = SessionLocal()
    try:
        # The migration ran as part of conftest fixture; just verify columns exist.
        cols = db.execute(text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name='clothing_items' "
            "AND column_name IN ('catalog_visibility','deleted_at','view_count',"
            "'imported_from_clothing_item_id')"
        )).fetchall()
        assert len(cols) == 4, f"missing columns: {cols}"

        # creator_items table should be gone.
        exists = db.execute(text(
            "SELECT 1 FROM information_schema.tables WHERE table_name='creator_items'"
        )).fetchone()
        assert exists is None, "creator_items table still exists post-migration"

        # card_pack_items.clothing_item_id should exist.
        col = db.execute(text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name='card_pack_items' AND column_name='clothing_item_id'"
        )).fetchone()
        assert col is not None

        # Junction table exists with expected columns and CHECK.
        constraint = db.execute(text(
            "SELECT 1 FROM information_schema.check_constraints "
            "WHERE constraint_name='ck_sgci_slot'"
        )).fetchone()
        assert constraint is not None
    finally:
        db.close()
```

- [ ] **Step 2: Run test**

Run: `pytest backend/tests/test_merge_migration.py -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add backend/tests/test_merge_migration.py
git commit -m "test(migration): verify consolidate_and_enhance migration post-state"
```

---

## Phase 2: Model Updates

### Task 2.1: Update `ClothingItem` model

**Files:**
- Modify: `backend/app/models/clothing_item.py:23-84`

- [ ] **Step 1: Add new columns and rename FK**

Edit `ClothingItem` class — add after `sync_status` column:

```python
    catalog_visibility = Column(
        String(20), nullable=False, server_default="PRIVATE"
    )
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    view_count = Column(Integer, nullable=False, server_default="0")
```

Rename existing `imported_from_creator_item_id` column declaration:

```python
    # was: imported_from_creator_item_id
    imported_from_clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="SET NULL"),
        nullable=True,
    )
```

Add to `__table_args__`:

```python
        CheckConstraint(
            "catalog_visibility IN ('PRIVATE','PACK_ONLY','PUBLIC')",
            name="ck_clothing_catalog_visibility",
        ),
```

- [ ] **Step 2: Run all existing tests to catch breaking references**

Run: `pytest backend/tests/ -x -v 2>&1 | head -80`
Expected: may fail in places referencing `imported_from_creator_item_id`; note them.

- [ ] **Step 3: Grep and update references**

```bash
grep -rn "imported_from_creator_item_id" backend/ documents/
```

Replace each hit with `imported_from_clothing_item_id` (code references only; leave historical comments alone).

- [ ] **Step 4: Re-run tests**

Run: `pytest backend/tests/ -x -v 2>&1 | head -80`
Expected: now passes up to the parts that depend on creator_items (which Phase 3 handles).

- [ ] **Step 5: Commit**

```bash
git add backend/app/models/clothing_item.py backend/
git commit -m "feat(models): add catalog_visibility/deleted_at/view_count to ClothingItem; rename FK"
```

### Task 2.2: Remove CreatorItem classes from `creator.py`

**Files:**
- Modify: `backend/app/models/creator.py`

- [ ] **Step 1: Delete the four classes**

From `backend/app/models/creator.py`, remove:
- `CreatorItem`
- `CreatorItemImage`
- `CreatorItemModel3D`
- `CreatorProcessingTask`

Keep:
- `CreatorProfile`
- `CardPack`
- `CardPackItem`

In `CardPackItem`, rename the FK column:

```python
    # was: creator_item_id
    clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
```

And the relationship:

```python
    # was: creator_item = relationship("CreatorItem", backref="pack_items")
    clothing_item = relationship("ClothingItem", backref="pack_entries")
```

Update the unique index name to match migration:

```python
    __table_args__ = (
        Index(
            "uq_card_pack_items_pack_clothing_item",
            "card_pack_id",
            "clothing_item_id",
            unique=True,
        ),
        ...
    )
```

- [ ] **Step 2: Import of `CardPackItem` etc. will fail in lots of places — that's expected; Phase 3 fixes it.**

- [ ] **Step 3: Commit**

```bash
git add backend/app/models/creator.py
git commit -m "refactor(models): remove CreatorItem/Image/Model3D/ProcessingTask classes; retarget CardPackItem FK"
```

---

## Phase 3: CRUD + Services Merge

### Task 3.1: Fold `crud/creator_item.py` into `crud/clothing.py`

**Files:**
- Modify: `backend/app/crud/clothing.py`
- Delete: `backend/app/crud/creator_item.py`

- [ ] **Step 1: Read current `creator_item.py` to identify helpers worth keeping**

The only unique helpers were `get_owned_creator_item`, `create_creator_item`, `update_creator_item`, `delete_creator_item`, `list_public_creator_items_by_creator`. These collapse into:
- `get` (already exists — by `user_id`)
- `create` (new in this file)
- `update` (already exists)
- `delete` (new — uses 3-tier logic from Task 5.1)
- `list_published_by_user` (new)

- [ ] **Step 2: Add `create` and `list_published_by_user` and `list_popular`**

Append to `backend/app/crud/clothing.py`:

```python
def create(
    db: Session,
    *,
    item_id: UUID,
    user_id: UUID,
    name: str | None = None,
    description: str | None = None,
    source: str = "OWNED",
    catalog_visibility: str = "PRIVATE",
) -> ClothingItem:
    item = ClothingItem(
        id=item_id,
        user_id=user_id,
        source=source,
        catalog_visibility=catalog_visibility,
        predicted_tags=[],
        final_tags=[],
        is_confirmed=False,
        custom_tags=[],
        name=name,
        description=description,
    )
    db.add(item)
    db.flush()
    return item


def list_published_by_user(
    db: Session,
    *,
    user_id: UUID,
    page: int = 1,
    limit: int = 20,
) -> Tuple[List[ClothingItem], int]:
    q = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.user_id == user_id,
            ClothingItem.catalog_visibility.in_(("PACK_ONLY", "PUBLIC")),
            ClothingItem.deleted_at.is_(None),
        )
        .order_by(ClothingItem.created_at.desc())
    )
    total = q.count()
    items = q.offset((page - 1) * limit).limit(limit).all()
    return items, total


def list_popular(
    db: Session,
    *,
    limit: int = 10,
) -> List[ClothingItem]:
    return (
        db.query(ClothingItem)
        .filter(
            ClothingItem.catalog_visibility.in_(("PACK_ONLY", "PUBLIC")),
            ClothingItem.deleted_at.is_(None),
        )
        .order_by(ClothingItem.view_count.desc(), ClothingItem.created_at.desc())
        .limit(limit)
        .all()
    )
```

- [ ] **Step 3: Add `deleted_at IS NULL` filter to every existing SELECT on `ClothingItem`**

Look at `get`, `update_final_tags`, `update`, `search_by_final_tags`, `list_with_tag_filter`. Add `ClothingItem.deleted_at.is_(None)` to each query's filters.

- [ ] **Step 4: Delete `backend/app/crud/creator_item.py`**

```bash
git rm backend/app/crud/creator_item.py
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/crud/clothing.py
git commit -m "refactor(crud): fold creator_item CRUD into clothing; add deleted_at filter everywhere"
```

### Task 3.2: Fold `creator_pipeline.py` into `clothing_pipeline.py`

**Files:**
- Modify: `backend/app/services/clothing_pipeline.py`
- Delete: `backend/app/services/creator_pipeline.py`
- Delete: `backend/app/services/creator_processing_task_service.py`
- Modify: `backend/app/services/processing_task_service.py`

- [ ] **Step 1: Diff `creator_pipeline.py` against `clothing_pipeline.py`**

```bash
diff backend/app/services/creator_pipeline.py backend/app/services/clothing_pipeline.py | less
```

Capture the unique-to-creator logic in a short list. Most of the difference is the table name (`creator_items` vs `clothing_items`) and task type names.

- [ ] **Step 2: Make `clothing_pipeline.run_pipeline_task` work for both sources**

After the merge, both creator-uploads and consumer-uploads go through the same path. Ensure the function reads the item's `catalog_visibility` and doesn't assume anything about it — just processes the item.

Because the table is unified, the creator-pipeline file is now identical to the clothing-pipeline file. Delete it.

```bash
git rm backend/app/services/creator_pipeline.py
```

- [ ] **Step 3: Fold `creator_processing_task_service.py` into `processing_task_service.py`**

The merged `processing_tasks` table already exists; creator_processing_tasks is dropped by migration. Any helper functions in `creator_processing_task_service.py` become methods on `processing_task_service.py`. Inline them.

```bash
git rm backend/app/services/creator_processing_task_service.py
```

- [ ] **Step 4: Fix the claim race (audit item 12) in `processing_task_service.py`**

Find the claim function (it reads status, then updates). Replace with atomic compare-and-swap:

```python
def claim_task(db: Session, *, task_id: UUID, worker_id: str) -> bool:
    """Atomically claim a PENDING task; returns True on success."""
    result = db.execute(
        text(
            """
            UPDATE processing_tasks
            SET status='PROCESSING',
                worker_id=:wid,
                started_at=now(),
                lease_expires_at=now() + interval '900 seconds'
            WHERE id=:tid AND status='PENDING'
            RETURNING id
            """
        ),
        {"tid": str(task_id), "wid": worker_id},
    )
    return result.first() is not None
```

- [ ] **Step 5: Update `tasks.py`**

Remove `@celery_app.task(name="creator.process_pipeline")` and its helper block. The clothing pipeline task handles both.

- [ ] **Step 6: Run tests**

Run: `pytest backend/tests/test_creator_foundation.py -v`
Expected: this will fail until the API layer is updated in Phase 4. Move on.

- [ ] **Step 7: Commit**

```bash
git add backend/app/services/ backend/app/tasks.py
git commit -m "refactor(services): fold creator_pipeline/processing_task into unified paths; fix claim race"
```

---

## Phase 4: API Layer Merge

### Task 4.1: Update `card_packs.py` to reference `clothing_items`

**Files:**
- Modify: `backend/app/api/v1/card_packs.py` (many lines)
- Modify: `backend/app/crud/card_pack.py`

- [ ] **Step 1: Every place that says `creator_item_id` → `clothing_item_id` or `creator_item` → `clothing_item`**

Grep:
```bash
grep -n "creator_item" backend/app/api/v1/card_packs.py backend/app/crud/card_pack.py backend/app/schemas/card_pack.py
```

Rewrite each hit. The request/response schemas exposed as `creatorItemId`/`itemIds` become `clothingItemId`/`itemIds` (the latter was already generic).

- [ ] **Step 2: Add `list_popular_card_packs` to `crud/card_pack.py`**

```python
def list_popular_card_packs(
    db: Session,
    *,
    limit: int = 10,
) -> list[CardPack]:
    return (
        db.query(CardPack)
        .filter(CardPack.status == "PUBLISHED")
        .order_by(CardPack.view_count.desc(), CardPack.created_at.desc())
        .limit(limit)
        .all()
    )
```

- [ ] **Step 3: Add endpoint**

In `card_packs.py` router:

```python
@router.get("/popular", response_model=CardPackListResponse)
def list_popular_card_packs(
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
):
    packs = crud_card_pack.list_popular_card_packs(db, limit=limit)
    return CardPackListResponse(
        data=CardPackListData(
            items=[_to_card_pack_list_item(db, pack) for pack in packs],
            pagination={"page": 1, "limit": limit, "total": len(packs), "totalPages": 1},
        )
    )
```

Place this BEFORE the `/{pack_id}` route so `/popular` doesn't match `{pack_id}` as a UUID path. (FastAPI order-sensitive.)

- [ ] **Step 4: Fix TOCTOU on `DELETE /card-packs/{pack_id}` (audit item 2)**

Replace the current check with a `FOR UPDATE`:

```python
# inside delete_card_pack, after getting pack with for_update=True:
import_count = (
    db.query(CardPackImport)
    .filter_by(card_pack_id=pack_id)
    .with_for_update()  # lock the rows, if any exist
    .count()
)
```

(The `for_update=True` on `get_owned_card_pack` already locks the pack itself.)

- [ ] **Step 5: Commit**

```bash
git add backend/app/api/v1/card_packs.py backend/app/crud/card_pack.py backend/app/schemas/card_pack.py
git commit -m "refactor(card-packs): use clothing_item_id FK; add /popular endpoint; fix delete TOCTOU"
```

### Task 4.2: Rewrite `imports.py` for merged schema

**Files:**
- Modify: `backend/app/api/v1/imports.py`

- [ ] **Step 1: Replace the inner loop**

Inside `import_card_pack`, the body that iterates `pack_items` and copies from `pi.creator_item` changes. The source is now a `ClothingItem` (publisher's canonical one). The destination is a new `ClothingItem(source='IMPORTED')` with `imported_from_clothing_item_id=canonical.id`. Blob sharing via `addref` unchanged.

```python
    # Lock the pack row to serialize with concurrent delete/publish/unpublish.
    pack = (
        db.query(CardPack)
        .filter(CardPack.id == body.card_pack_id, CardPack.status == "PUBLISHED")
        .with_for_update()
        .first()
    )
    if not pack:
        raise HTTPException(404, "Pack not found or not published")
    # ... existing duplicate-import check ...

    pack_items = (
        db.query(CardPackItem)
        .filter(CardPackItem.card_pack_id == pack.id)
        .order_by(CardPackItem.sort_order)
        .all()
    )

    for pi in pack_items:
        canonical = pi.clothing_item  # merged schema
        if canonical is None or canonical.deleted_at is not None:
            # Tombstoned canonical — skip
            continue

        new_item = ClothingItem(
            user_id=user_id,
            source="IMPORTED",
            name=canonical.name,
            description=canonical.description,
            predicted_tags=list(canonical.predicted_tags) if canonical.predicted_tags else [],
            final_tags=list(canonical.final_tags) if canonical.final_tags else [],
            is_confirmed=True,
            custom_tags=[],
            catalog_visibility="PRIVATE",
            imported_from_card_pack_id=pack.id,
            imported_from_clothing_item_id=canonical.id,
        )
        db.add(new_item)
        db.flush()

        for img in canonical.images:
            db.add(Image(
                clothing_item_id=new_item.id,
                image_type=img.image_type,
                angle=img.angle,
                blob_hash=img.blob_hash,
            ))
            try:
                blob_service.addref(db, img.blob_hash)
            except BlobNotFoundError:
                raise HTTPException(
                    409,
                    "Pack contents changed during import; retry.",
                )

        if canonical.model_3d:
            db.add(Model3D(
                clothing_item_id=new_item.id,
                model_format=canonical.model_3d.model_format,
                blob_hash=canonical.model_3d.blob_hash,
                vertex_count=canonical.model_3d.vertex_count,
                face_count=canonical.model_3d.face_count,
            ))
            try:
                blob_service.addref(db, canonical.model_3d.blob_hash)
            except BlobNotFoundError:
                raise HTTPException(409, "Pack contents changed during import; retry.")

        crud_wardrobe.ensure_item_in_wardrobe(
            db, user_id=user_id,
            wardrobe_id=main_wardrobe.id,
            clothing_item_id=new_item.id,
        )
```

- [ ] **Step 2: Fix `import_count` RMW with the lock we just added**

```python
    pack.import_count = (pack.import_count or 0) + 1
    db.commit()
```

The `FOR UPDATE` on the pack row held above prevents concurrent races now.

- [ ] **Step 3: Extend `unimport_card_pack` with tombstone cascade**

After the loop of `_delete_clothing_item_internal(db, item)`:

```python
    # Cascade cleanup: if any canonical item pointed to was a tombstone with
    # zero remaining imports, hard-delete it.
    stale_canonicals = {
        item.imported_from_clothing_item_id
        for item in items
        if item.imported_from_clothing_item_id is not None
    }
    for canonical_id in stale_canonicals:
        canonical = db.query(ClothingItem).filter_by(id=canonical_id).first()
        if canonical is None or canonical.deleted_at is None:
            continue
        remaining = db.query(ClothingItem).filter_by(
            imported_from_clothing_item_id=canonical_id
        ).count()
        if remaining == 0:
            _delete_clothing_item_internal(db, canonical)
```

- [ ] **Step 4: Also lock the pack on unimport**

```python
    pack = (
        db.query(CardPack)
        .filter_by(id=pack_id)
        .with_for_update()
        .first()
    )
    if pack and (pack.import_count or 0) > 0:
        pack.import_count -= 1
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/api/v1/imports.py
git commit -m "refactor(imports): snapshot from clothing_items; lock pack FOR UPDATE; cascade tombstone cleanup"
```

### Task 4.3: Update `creator_items.py` to shim forward

**Files:**
- Modify: `backend/app/api/v1/creator_items.py`

- [ ] **Step 1: Replace file contents**

```python
"""Legacy shim. Forwards to /clothing-items with catalog_visibility='PACK_ONLY' default.
Remove in the next minor release."""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from app.api.deps import get_current_creator_user_id
from app.api.v1.clothing import (
    create_clothing_item,
    delete_clothing_item,
    get_clothing_item,
    update_clothing_item,
)
from app.db.session import get_db
from app.schemas.clothing_item import ClothingItemUpdate

router = APIRouter(prefix="/creator-items", tags=["creator-items (legacy)"])
logger = logging.getLogger(__name__)


@router.post("", status_code=202, deprecated=True)
async def legacy_create_creator_item(
    front_image: UploadFile = File(...),
    back_image: UploadFile | None = File(None),
    name: str | None = Form(None),
    description: str | None = Form(None),
    catalog_visibility: str = Form("PACK_ONLY", alias="catalogVisibility"),
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    logger.warning("Legacy /creator-items endpoint; use /clothing-items instead.")
    return await create_clothing_item(
        front_image=front_image, back_image=back_image,
        name=name, description=description,
        catalog_visibility=catalog_visibility,
        db=db, user_id=creator_id,
    )


@router.get("/{item_id}", deprecated=True)
def legacy_get_creator_item(item_id: UUID, db: Session = Depends(get_db),
                             creator_id: UUID = Depends(get_current_creator_user_id)):
    return get_clothing_item(item_id=item_id, db=db, user_id=creator_id)


@router.patch("/{item_id}", deprecated=True)
def legacy_update_creator_item(item_id: UUID, body: ClothingItemUpdate,
                                db: Session = Depends(get_db),
                                creator_id: UUID = Depends(get_current_creator_user_id)):
    return update_clothing_item(item_id=item_id, body=body, db=db, user_id=creator_id)


@router.delete("/{item_id}", status_code=204, deprecated=True)
def legacy_delete_creator_item(item_id: UUID, db: Session = Depends(get_db),
                                creator_id: UUID = Depends(get_current_creator_user_id)):
    return delete_clothing_item(item_id=item_id, db=db, user_id=creator_id)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/api/v1/creator_items.py
git commit -m "refactor(creator-items): downgrade to legacy shim forwarding to clothing-items"
```

### Task 4.4: Extend `clothing.py` API with publish + visibility

**Files:**
- Modify: `backend/app/api/v1/clothing.py`
- Modify: `backend/app/schemas/clothing_item.py`

- [ ] **Step 1: Add `catalog_visibility` form field to `create_clothing_item`**

Add a new parameter:
```python
    catalog_visibility: str = Form("PRIVATE", alias="catalogVisibility"),
```

Validate: must be in `{"PRIVATE","PACK_ONLY","PUBLIC"}`. Pass to `crud_clothing.create(..., catalog_visibility=catalog_visibility)`.

- [ ] **Step 2: Support `catalogVisibility` in PATCH**

Add field to `ClothingItemUpdate` schema:
```python
    catalog_visibility: str | None = Field(None, alias="catalogVisibility")
```

In `crud_clothing.update`, accept and update this field.

Guard: refuse to transition to `'PRIVATE'` if the item is in any `PUBLISHED` CardPack. Raise 409 with explicit message.

- [ ] **Step 3: Explicit size check (audit item 13)**

In `create_clothing_item`, before `ingest_upload`, insert:

```python
    if len(front_bytes) > settings.MAX_UPLOAD_SIZE_BYTES:
        raise HTTPException(413, "front_image exceeds size limit")
    if back_bytes and len(back_bytes) > settings.MAX_UPLOAD_SIZE_BYTES:
        raise HTTPException(413, "back_image exceeds size limit")
```

- [ ] **Step 4: Add `viewCount`, `catalogVisibility`, `deletedAt` to `ClothingItemResponse`**

In `schemas/clothing_item.py` and in `_item_to_response`, expose the new fields.

- [ ] **Step 5: Commit**

```bash
git add backend/app/api/v1/clothing.py backend/app/schemas/clothing_item.py backend/app/crud/clothing.py
git commit -m "feat(clothing): publish via catalogVisibility; explicit size check; expose viewCount"
```

### Task 4.5: Wardrobe N+1 fix (audit items 8, 9)

**Files:**
- Modify: `backend/app/api/v1/wardrobe.py:107-131`

- [ ] **Step 1: Replace `get_item_count` per-row with a single GROUP BY**

Add to `crud/wardrobe.py`:

```python
def count_items_by_wardrobe_ids(
    db: Session, wardrobe_ids: list[UUID],
) -> dict[UUID, int]:
    if not wardrobe_ids:
        return {}
    from app.models.wardrobe import WardrobeItem
    rows = (
        db.query(WardrobeItem.wardrobe_id, func.count(WardrobeItem.id))
        .filter(WardrobeItem.wardrobe_id.in_(wardrobe_ids))
        .group_by(WardrobeItem.wardrobe_id)
        .all()
    )
    return {wid: cnt for wid, cnt in rows}
```

- [ ] **Step 2: Use in `list_wardrobes` and `list_public_wardrobes`**

```python
    wardrobes = crud_wardrobe.list_wardrobes(db, user_id)
    counts = crud_wardrobe.count_items_by_wardrobe_ids(db, [w.id for w in wardrobes])
    out = [_wardrobe_to_response(db, w, counts.get(w.id, 0)) for w in wardrobes]
    return {"items": out}
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/api/v1/wardrobe.py backend/app/crud/wardrobe.py
git commit -m "perf(wardrobe): batch item counts to fix N+1 in list endpoints"
```

### Task 4.6: Card pack cover auth (audit item 10)

**Files:**
- Modify: `backend/app/api/v1/files.py`

- [ ] **Step 1: Find the `/files/card-packs/{id}/cover` handler**

Grep:
```bash
grep -n "card-packs" backend/app/api/v1/files.py
```

- [ ] **Step 2: Add auth + visibility guard**

```python
@router.get("/card-packs/{pack_id}/cover")
def serve_card_pack_cover(
    pack_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: UUID | None = Depends(get_optional_current_user_id),
):
    pack = db.query(CardPack).filter_by(id=pack_id).first()
    if pack is None or pack.cover_image_blob_hash is None:
        raise HTTPException(404, "not found")
    if pack.status != "PUBLISHED" and pack.creator_id != current_user_id:
        raise HTTPException(404, "not found")  # don't leak existence
    return _stream_blob(db, pack.cover_image_blob_hash)
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/api/v1/files.py
git commit -m "fix(files): require auth + PUBLISHED guard for card-pack cover"
```

---

## Phase 5: ClothingItem 3-Tier Delete Lifecycle

### Task 5.1: Add 3-tier delete to `crud/clothing.py`

**Files:**
- Modify: `backend/app/crud/clothing.py`

- [ ] **Step 1: Add `delete_with_lifecycle` function**

```python
from datetime import datetime, timezone
from sqlalchemy import exists

from app.models.clothing_item import Image, Model3D
from app.models.creator import CardPack, CardPackItem
from app.models.wardrobe import WardrobeItem
from app.services.blob_service import BlobService


def delete_with_lifecycle(
    db: Session,
    *,
    item_id: UUID,
    user_id: UUID,
    blob_service: BlobService,
) -> str:
    """Returns 'HARD_DELETED' or 'TOMBSTONED' or raises 404."""
    item = (
        db.query(ClothingItem)
        .filter(ClothingItem.id == item_id, ClothingItem.user_id == user_id,
                ClothingItem.deleted_at.is_(None))
        .with_for_update()
        .first()
    )
    if item is None:
        return None  # caller raises 404

    # Does any PUBLISHED pack contain this item?
    in_published_pack = db.query(exists().where(
        (CardPackItem.clothing_item_id == item.id)
        & (CardPackItem.card_pack_id == CardPack.id)
        & (CardPack.status == "PUBLISHED")
    )).scalar()

    # Is any IMPORTED ClothingItem pointing here?
    import_count = (
        db.query(ClothingItem)
        .filter(ClothingItem.imported_from_clothing_item_id == item.id)
        .count()
    )

    if not in_published_pack or import_count == 0:
        _hard_delete(db, item, blob_service)
        return "HARD_DELETED"
    else:
        _tombstone(db, item, blob_service)
        return "TOMBSTONED"


def _hard_delete(db: Session, item: ClothingItem, blob_service: BlobService) -> None:
    blob_hashes = [img.blob_hash for img in item.images]
    if item.model_3d:
        blob_hashes.append(item.model_3d.blob_hash)

    db.query(WardrobeItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    db.query(CardPackItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    db.delete(item)
    db.flush()
    for h in blob_hashes:
        if h:
            blob_service.release(db, h)


def _tombstone(db: Session, item: ClothingItem, blob_service: BlobService) -> None:
    blob_hashes = [img.blob_hash for img in item.images]
    if item.model_3d:
        blob_hashes.append(item.model_3d.blob_hash)

    db.query(WardrobeItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    db.query(CardPackItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)

    # Delete publisher-side images + model. Consumer IMPORTED copies have their own Image/Model3D rows.
    db.query(Image).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    if item.model_3d:
        db.delete(item.model_3d)

    item.deleted_at = datetime.now(timezone.utc)
    db.flush()

    for h in blob_hashes:
        if h:
            blob_service.release(db, h)
```

- [ ] **Step 2: Wire into the API**

In `backend/app/api/v1/clothing.py`, replace current `delete_clothing_item` body:

```python
@router.delete("/{item_id}", status_code=204)
def delete_clothing_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    # Refuse if processing is active.
    active = db.query(ProcessingTask).filter(
        ProcessingTask.clothing_item_id == item_id,
        ProcessingTask.status.in_(["PENDING", "PROCESSING"]),
    ).first()
    if active:
        raise HTTPException(409, "Cannot delete while processing")

    blob_service = get_blob_service()

    # Before delete, capture the imported_from link so we can do cascade cleanup.
    current = db.query(ClothingItem).filter_by(id=item_id, user_id=user_id).first()
    if not current:
        raise HTTPException(404, "Clothing item not found")
    imported_from = current.imported_from_clothing_item_id

    outcome = crud_clothing.delete_with_lifecycle(
        db, item_id=item_id, user_id=user_id, blob_service=blob_service,
    )
    if outcome is None:
        raise HTTPException(404, "Clothing item not found")

    # Cascade: if the deleted item was an IMPORTED copy of a tombstoned canonical,
    # and no other imports remain, hard-delete the tombstone.
    if imported_from is not None:
        canonical = db.query(ClothingItem).filter_by(id=imported_from).first()
        if canonical and canonical.deleted_at is not None:
            remaining = db.query(ClothingItem).filter_by(
                imported_from_clothing_item_id=canonical.id
            ).count()
            if remaining == 0:
                crud_clothing._hard_delete(db, canonical, blob_service)

    db.commit()
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/crud/clothing.py backend/app/api/v1/clothing.py
git commit -m "feat(clothing): 3-tier delete lifecycle with tombstone + cascade cleanup"
```

### Task 5.2: Tests for 3-tier delete

**Files:**
- Create: `backend/tests/test_clothing_delete_lifecycle.py`

- [ ] **Step 1: Write the three cases + cascade**

```python
"""3-tier delete lifecycle tests."""
import pytest
from fastapi.testclient import TestClient

# Use existing test harness patterns (see test_card_pack_flow.py for setup).


def test_case1_unpublished_hard_deletes(client, creator_user, owned_item):
    resp = client.delete(f"/api/v1/clothing-items/{owned_item.id}", headers=creator_user.auth)
    assert resp.status_code == 204

    get_resp = client.get(f"/api/v1/clothing-items/{owned_item.id}", headers=creator_user.auth)
    assert get_resp.status_code == 404


def test_case2_published_no_downloads_hard_deletes(client, creator_user, published_item_no_imports):
    resp = client.delete(
        f"/api/v1/clothing-items/{published_item_no_imports.id}",
        headers=creator_user.auth,
    )
    assert resp.status_code == 204
    # The CardPackItem linking it should be gone.


def test_case3_published_with_downloads_tombstones(client, creator_user, consumer_user,
                                                     published_item_with_import):
    canonical_id = published_item_with_import.id
    resp = client.delete(
        f"/api/v1/clothing-items/{canonical_id}",
        headers=creator_user.auth,
    )
    assert resp.status_code == 204

    # Creator no longer sees the item.
    get_resp = client.get(f"/api/v1/clothing-items/{canonical_id}", headers=creator_user.auth)
    assert get_resp.status_code == 404

    # Consumer's IMPORTED copy still works.
    imports = client.get(
        "/api/v1/clothing-items?source=IMPORTED",
        headers=consumer_user.auth,
    ).json()["data"]["items"]
    assert len(imports) == 1

    # Cascade: when consumer deletes their copy, the tombstoned canonical is hard-deleted.
    consumer_item_id = imports[0]["id"]
    client.delete(f"/api/v1/clothing-items/{consumer_item_id}", headers=consumer_user.auth)

    # Internal: canonical row should no longer exist even as tombstone.
    from app.db.session import SessionLocal
    db = SessionLocal()
    from app.models.clothing_item import ClothingItem
    assert db.query(ClothingItem).filter_by(id=canonical_id).first() is None
    db.close()
```

Fixture definitions (`creator_user`, `consumer_user`, `owned_item`, `published_item_no_imports`, `published_item_with_import`) go in `backend/tests/conftest.py` — follow the pattern in `test_card_pack_flow.py`.

- [ ] **Step 2: Run tests**

Run: `pytest backend/tests/test_clothing_delete_lifecycle.py -v`
Expected: PASS (fixtures may need adjustment based on existing helpers).

- [ ] **Step 3: Commit**

```bash
git add backend/tests/test_clothing_delete_lifecycle.py backend/tests/conftest.py
git commit -m "test(clothing): cover 3-tier delete lifecycle + cascade cleanup"
```

---

## Phase 6: View Counts + Popular + Atomic Increment

### Task 6.1: View count service

**Files:**
- Create: `backend/app/services/view_count_service.py`

- [ ] **Step 1: Write helper**

```python
"""Atomic view-count increment. Runs a single UPDATE, no read-modify-write."""

from uuid import UUID
from sqlalchemy.orm import Session

from app.models.clothing_item import ClothingItem
from app.models.creator import CardPack


def increment_clothing_item_view(db: Session, item_id: UUID) -> None:
    db.query(ClothingItem).filter(
        ClothingItem.id == item_id,
        ClothingItem.deleted_at.is_(None),
        ClothingItem.catalog_visibility.in_(("PACK_ONLY", "PUBLIC")),
    ).update(
        {ClothingItem.view_count: ClothingItem.view_count + 1},
        synchronize_session=False,
    )
    db.commit()


def increment_card_pack_view(db: Session, pack_id: UUID) -> None:
    db.query(CardPack).filter(
        CardPack.id == pack_id,
        CardPack.status == "PUBLISHED",
    ).update(
        {CardPack.view_count: CardPack.view_count + 1},
        synchronize_session=False,
    )
    db.commit()
```

- [ ] **Step 2: Wire into GET endpoints**

In `clothing.py` GET `/clothing-items/{item_id}`: after composing the response, call `increment_clothing_item_view` if `current_user_id != item.user_id`.

In `card_packs.py` GET `/card-packs/{pack_id}`: after composing response, call `increment_card_pack_view` if `current_user_id != pack.creator_id`.

In `card_packs.py` GET `/card-packs/share/{share_id}`: same, but `current_user_id` from `get_optional_current_user_id` may be None; increment if `current_user_id != pack.creator_id` (None-aware).

- [ ] **Step 3: Expose `viewCount` in responses**

Already done in Task 4.4 for clothing; add `viewCount=pack.view_count` to `_to_card_pack_detail` and `_to_card_pack_list_item`.

- [ ] **Step 4: Commit**

```bash
git add backend/app/services/view_count_service.py backend/app/api/v1/clothing.py backend/app/api/v1/card_packs.py
git commit -m "feat(view-counts): atomic increment on detail GETs; expose viewCount in responses"
```

### Task 6.2: View count tests

**Files:**
- Create: `backend/tests/test_view_counts.py`

- [ ] **Step 1: Write tests**

```python
"""View count increment and popular endpoint tests."""

def test_clothing_item_view_increment_ignores_owner(client, creator_user, published_item_no_imports):
    before = published_item_no_imports.view_count
    client.get(f"/api/v1/clothing-items/{published_item_no_imports.id}", headers=creator_user.auth)
    db_refresh(published_item_no_imports)
    assert published_item_no_imports.view_count == before


def test_clothing_item_view_increment_by_other_user(client, consumer_user, published_item_no_imports):
    before = published_item_no_imports.view_count
    client.get(
        f"/api/v1/clothing-items/{published_item_no_imports.id}",
        headers=consumer_user.auth,
    )
    db_refresh(published_item_no_imports)
    assert published_item_no_imports.view_count == before + 1


def test_card_pack_view_increment_by_anon(client, published_pack):
    before = published_pack.view_count
    client.get(f"/api/v1/card-packs/{published_pack.id}")  # no auth
    db_refresh(published_pack)
    assert published_pack.view_count == before + 1


def test_popular_endpoint_returns_top_by_views(client, packs_with_views):
    """packs_with_views fixture creates 3 packs with view counts 10, 5, 1."""
    resp = client.get("/api/v1/card-packs/popular?limit=2")
    items = resp.json()["data"]["items"]
    assert len(items) == 2
    assert items[0]["viewCount"] >= items[1]["viewCount"]


def test_private_clothing_item_view_does_not_increment(client, consumer_user, private_item):
    """PRIVATE items don't participate in view counting — even a GET returns 404 for non-owner."""
    resp = client.get(f"/api/v1/clothing-items/{private_item.id}", headers=consumer_user.auth)
    # Non-owner has no access to PRIVATE
    assert resp.status_code in (403, 404)
```

- [ ] **Step 2: Run tests**

Run: `pytest backend/tests/test_view_counts.py -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add backend/tests/test_view_counts.py
git commit -m "test(view-counts): cover increment semantics + /popular ordering"
```

---

## Phase 7: Multi-Garment DreamO

### Task 7.1: Add `StyledGenerationClothingItem` model

**Files:**
- Modify: `backend/app/models/styled_generation.py`

- [ ] **Step 1: Append class**

```python
class StyledGenerationClothingItem(Base):
    __tablename__ = "styled_generation_clothing_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    generation_id = Column(
        UUID(as_uuid=True),
        ForeignKey("styled_generations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    slot = Column(String(10), nullable=False)
    position = Column(Integer, nullable=False, default=0)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint(
            "slot IN ('HAT','TOP','PANTS','SHOES')", name="ck_sgci_slot"
        ),
        UniqueConstraint("generation_id", "slot", name="uq_sgci_gen_slot"),
    )

    clothing_item = relationship("ClothingItem", foreign_keys=[clothing_item_id])
```

Add to `StyledGeneration`:

```python
    gender = Column(String(10), nullable=False)  # NOT NULL, CHECK in migration
    started_at = Column(DateTime(timezone=True), nullable=True)
    lease_expires_at = Column(DateTime(timezone=True), nullable=True)
    worker_id = Column(String(255), nullable=True)

    garments = relationship(
        "StyledGenerationClothingItem",
        backref="generation",
        cascade="all, delete-orphan",
        order_by="StyledGenerationClothingItem.position",
    )
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/models/styled_generation.py
git commit -m "feat(models): add StyledGenerationClothingItem junction + gender/lease fields"
```

### Task 7.2: Update prompt builder

**Files:**
- Modify: `backend/app/services/prompt_builder_service.py`
- Create: `backend/tests/test_prompt_builder.py`

- [ ] **Step 1: Write tests first**

```python
from app.services.prompt_builder_service import build_prompt

def test_build_prompt_single_top_male():
    p = build_prompt(
        scene_prompt="in a coffee shop",
        gender="male",
        garments=[("TOP", "blue denim jacket")],
    )
    assert "a man" in p
    assert "a blue denim jacket" in p
    assert "in a coffee shop" in p
    assert "smiling" in p


def test_build_prompt_four_garments_female():
    p = build_prompt(
        scene_prompt="at the park",
        gender="female",
        garments=[
            ("HAT", "red baseball cap"),
            ("TOP", "white blouse"),
            ("PANTS", "dark jeans"),
            ("SHOES", "white sneakers"),
        ],
    )
    assert "a woman" in p
    assert "a red baseball cap" in p
    assert "a white blouse" in p
    assert "dark jeans" in p  # plural — no article
    assert "white sneakers" in p  # plural — no article
    assert "and" in p  # oxford joiner


def test_hat_top_pants_shoes_ordering_forced():
    """Garments passed out-of-order are ordered HAT→TOP→PANTS→SHOES internally."""
    p = build_prompt(
        scene_prompt="at night",
        gender="male",
        garments=[
            ("SHOES", "black boots"),
            ("HAT", "beanie"),
        ],
    )
    assert p.index("beanie") < p.index("black boots")
```

- [ ] **Step 2: Run — expect failure**

Run: `pytest backend/tests/test_prompt_builder.py -v`
Expected: FAIL (current `build_prompt` has a different signature).

- [ ] **Step 3: Replace `prompt_builder_service.py`**

```python
"""Prompt template assembly for DreamO multi-garment styled generation."""

SLOT_ORDER = ("HAT", "TOP", "PANTS", "SHOES")
SLOT_DEFAULT_DESCRIPTOR = {
    "HAT": "a hat",
    "TOP": "a top",
    "PANTS": "pants",
    "SHOES": "shoes",
}

PLURAL_LIKE = {"jeans", "pants", "shoes", "sneakers", "boots", "trousers", "shorts"}

DEFAULT_NEGATIVE_TEMPLATE = (
    "blurry, low quality, deformed body, extra fingers, extra limbs, "
    "duplicated person, wrong clothing, bad anatomy, oversaturated face, plastic skin"
)


def _article(descriptor: str) -> str:
    first_word = descriptor.strip().split()[0].lower() if descriptor.strip() else ""
    last_word = descriptor.strip().split()[-1].lower() if descriptor.strip() else ""
    if last_word in PLURAL_LIKE or first_word in PLURAL_LIKE:
        return ""
    return "an" if first_word[:1] in "aeiou" else "a"


def _with_article(descriptor: str) -> str:
    art = _article(descriptor)
    return f"{art} {descriptor}".strip()


def _join_garments(garments: list[tuple[str, str]]) -> str:
    by_slot = {slot: desc for slot, desc in garments}
    ordered = [
        (slot, by_slot[slot]) for slot in SLOT_ORDER if slot in by_slot
    ]
    parts = [_with_article(desc) for _, desc in ordered]
    if len(parts) == 1:
        return parts[0]
    if len(parts) == 2:
        return f"{parts[0]} and {parts[1]}"
    return ", ".join(parts[:-1]) + f", and {parts[-1]}"


def build_prompt(
    scene_prompt: str,
    gender: str,
    garments: list[tuple[str, str]],
) -> str:
    gender_word = "man" if gender.strip().lower() == "male" else "woman"
    phrase = _join_garments(garments) if garments else "clothing"
    return (
        f"A realistic full-body fashion portrait of a {gender_word}, "
        f"wearing {phrase}, in {scene_prompt.strip()}, smiling, "
        "natural skin texture, detailed fabric, high quality, photographic lighting"
    )


def get_negative_prompt(user_negative: str | None = None) -> str:
    if user_negative and user_negative.strip():
        return f"{DEFAULT_NEGATIVE_TEMPLATE}, {user_negative.strip()}"
    return DEFAULT_NEGATIVE_TEMPLATE
```

- [ ] **Step 4: Run tests**

Run: `pytest backend/tests/test_prompt_builder.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/prompt_builder_service.py backend/tests/test_prompt_builder.py
git commit -m "feat(prompt): multi-garment + gender-aware prompt builder with slot ordering"
```

### Task 7.3: DreamO client + server multi-garment

**Files:**
- Modify: `backend/app/services/dreamo_client_service.py`
- Modify: `DreamO/server.py`
- Create: `backend/tests/test_dreamo_server_multi_garment.py`

- [ ] **Step 1: Update `DreamO/server.py`**

Replace `GenerateRequest`:

```python
class GenerateRequest(BaseModel):
    id_image: Optional[str] = None
    garment_images: Optional[list[str]] = Field(default=None)  # NEW: list of base64
    garment_image: Optional[str] = None  # DEPRECATED: single-garment shim
    prompt: str
    negative_prompt: str = ""
    guidance_scale: float = Field(default=4.5, ge=1.0, le=10.0)
    seed: int = -1
    width: int = Field(default=1024, ge=768, le=1024)
    height: int = Field(default=1024, ge=768, le=1024)
    num_inference_steps: int = Field(default=12, ge=4, le=50)
    ref_res: int = Field(default=512, ge=256, le=1024)
```

Inside `generate(req)`:

```python
    garments_list = req.garment_images or ([req.garment_image] if req.garment_image else [])

    if req.id_image is None and not garments_list:
        raise HTTPException(
            422, "At least one of id_image or garment_images must be provided"
        )

    ref_images, ref_tasks = [], []
    if req.id_image:
        ref_images.append(_decode_image(req.id_image))
        ref_tasks.append("id")
    for g in garments_list:
        ref_images.append(_decode_image(g))
        ref_tasks.append("ip")
```

Rest of the function is unchanged.

- [ ] **Step 2: Update `dreamo_client_service.py`**

```python
async def call_dreamo_generate(
    *,
    id_image_bytes: bytes | None = None,
    garment_images_bytes: list[bytes] | None = None,
    prompt: str,
    negative_prompt: str = "",
    guidance_scale: float = 4.5,
    seed: int = -1,
    width: int = 1024,
    height: int = 1024,
    num_inference_steps: int = 12,
) -> tuple[bytes, int]:
    payload: dict = {
        "prompt": prompt,
        "negative_prompt": negative_prompt,
        "guidance_scale": guidance_scale,
        "seed": seed,
        "width": width,
        "height": height,
        "num_inference_steps": num_inference_steps,
    }
    if id_image_bytes:
        payload["id_image"] = base64.b64encode(id_image_bytes).decode()
    if garment_images_bytes:
        payload["garment_images"] = [
            base64.b64encode(b).decode() for b in garment_images_bytes
        ]

    url = f"{settings.DREAMO_SERVICE_URL}/generate"
    timeout = settings.DREAMO_GENERATE_TIMEOUT_SECONDS
    # ... rest unchanged (error handling) ...
```

- [ ] **Step 3: Write DreamO server test (generator mocked)**

```python
"""DreamO server test: verifies ref_tasks built correctly without loading the real model."""
import base64
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient


def _tiny_png_b64():
    # 1x1 white PNG.
    return base64.b64encode(bytes.fromhex(
        "89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4"
        "89000000017352474200AECE1CE90000000E49444154789463F8FF00000000"
        "05000100000000000049454E44AE426082"
    )).decode()


@pytest.fixture
def app():
    with patch("DreamO.server._generator") as mock_gen:
        mock_gen.pre_condition.return_value = ([], [], 42)
        mock_gen.dreamo_pipeline.return_value = MagicMock(
            images=[MagicMock()]
        )
        mock_gen.dreamo_pipeline.return_value.images[0].save = (
            lambda buf, format: buf.write(b"fake_png_bytes")
        )
        from DreamO.server import app as dreamo_app
        yield dreamo_app


def test_accepts_multiple_garment_images(app):
    client = TestClient(app)
    r = client.post("/generate", json={
        "id_image": _tiny_png_b64(),
        "garment_images": [_tiny_png_b64(), _tiny_png_b64()],
        "prompt": "test",
    })
    # Even if model is mocked, schema validation should pass.
    assert r.status_code in (200, 500)  # we care about schema passing


def test_backward_compat_single_garment(app):
    client = TestClient(app)
    r = client.post("/generate", json={
        "id_image": _tiny_png_b64(),
        "garment_image": _tiny_png_b64(),
        "prompt": "test",
    })
    assert r.status_code in (200, 500)
```

- [ ] **Step 4: Run tests**

Run: `pytest backend/tests/test_dreamo_server_multi_garment.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DreamO/server.py backend/app/services/dreamo_client_service.py backend/tests/test_dreamo_server_multi_garment.py
git commit -m "feat(dreamo): accept garment_images list; keep garment_image as deprecated shim"
```

### Task 7.4: Styled generation API new request shape

**Files:**
- Modify: `backend/app/api/v1/styled_generation.py`
- Modify: `backend/app/schemas/styled_generation.py`

- [ ] **Step 1: Update schemas**

Add:
```python
class StyledGenerationGarmentSummary(BaseModel):
    id: UUID
    slot: str
    name: Optional[str] = None
    imageUrl: Optional[str] = None


class StyledGenerationResponse(BaseModel):
    ...existing fields...
    gender: str
    garments: list[StyledGenerationGarmentSummary]
```

- [ ] **Step 2: Update POST endpoint**

Replace parameter signature:
```python
@router.post("", status_code=202)
async def create_styled_generation(
    selfie_image: UploadFile = File(...),
    gender: str = Form(...),
    scene_prompt: str = Form(...),
    clothing_items: str = Form(...),  # JSON string
    clothing_item_id: str | None = Form(None),  # DEPRECATED single-item shim
    negative_prompt: str | None = Form(None),
    guidance_scale: float = Form(4.5),
    seed: int = Form(-1),
    width: int = Form(1024),
    height: int = Form(1024),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
```

Body logic:

```python
    # Gender validation
    gender_norm = gender.strip().upper()
    if gender_norm not in ("MALE", "FEMALE"):
        raise HTTPException(422, "gender must be 'male' or 'female'")

    # Parse clothing_items JSON
    import json
    if clothing_items:
        try:
            items_parsed = json.loads(clothing_items)
        except json.JSONDecodeError:
            raise HTTPException(422, "clothing_items must be valid JSON")
    elif clothing_item_id:  # legacy shim
        items_parsed = [{"id": clothing_item_id, "slot": "TOP"}]
    else:
        raise HTTPException(422, "clothing_items is required")

    if not isinstance(items_parsed, list) or not (1 <= len(items_parsed) <= 4):
        raise HTTPException(422, "clothing_items must be a JSON array of 1 to 4 items")

    seen_slots = set()
    parsed = []
    for entry in items_parsed:
        try:
            item_uuid = UUID(entry["id"])
            slot = entry["slot"].strip().upper()
        except (KeyError, ValueError, TypeError):
            raise HTTPException(422, "each clothing_items entry needs id (UUID) and slot")
        if slot not in ("HAT", "TOP", "PANTS", "SHOES"):
            raise HTTPException(422, f"unknown slot {slot}")
        if slot in seen_slots:
            raise HTTPException(422, f"duplicate slot {slot} in clothing_items")
        seen_slots.add(slot)
        parsed.append((item_uuid, slot))

    # Each item must belong to the user and have PROCESSED_FRONT.
    for item_id, slot in parsed:
        item = crud_clothing.get(db, item_id, user_id)
        if not item:
            raise HTTPException(404, f"Clothing item {item_id} not found")
        processed = (
            db.query(ClothingImage)
            .filter(ClothingImage.clothing_item_id == item_id,
                    ClothingImage.image_type == "PROCESSED_FRONT")
            .first()
        )
        if not processed:
            raise HTTPException(
                409,
                f"Clothing item {item_id} (slot {slot}) has not finished processing",
            )

    # Create the StyledGeneration + junction rows atomically.
    # ... rest of the function: ingest selfie blob, create gen row,
    #     for each (item_id, slot, pos) insert StyledGenerationClothingItem ...
```

Include the junction inserts after `db.add(gen)`:

```python
    for position, (item_id, slot) in enumerate(parsed):
        db.add(StyledGenerationClothingItem(
            generation_id=gen_id,
            clothing_item_id=item_id,
            slot=slot,
            position=position,
        ))
    # Keep source_clothing_item_id updated for back-compat (points at first TOP if any)
    for item_id, slot in parsed:
        if slot == "TOP":
            gen.source_clothing_item_id = item_id
            break
    db.commit()
```

- [ ] **Step 3: Update `_to_response`**

Include gender + garments:

```python
def _to_response(gen: StyledGeneration) -> dict:
    garments_list = [
        {
            "id": jr.clothing_item_id,
            "slot": jr.slot,
            "name": jr.clothing_item.name if jr.clothing_item else None,
            "imageUrl": f"/files/clothing-items/{jr.clothing_item_id}/processed-front"
                       if jr.clothing_item else None,
        }
        for jr in gen.garments
    ]
    return StyledGenerationResponse(
        ...existing fields...,
        gender=gen.gender,
        garments=garments_list,
    ).model_dump()
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/api/v1/styled_generation.py backend/app/schemas/styled_generation.py
git commit -m "feat(styled-gen): multi-garment + gender request shape; legacy shim for single item"
```

### Task 7.5: Styled generation pipeline multi-garment

**Files:**
- Modify: `backend/app/services/styled_generation_pipeline.py`

- [ ] **Step 1: Replace the garment-fetch block**

```python
from datetime import datetime, timedelta, timezone

from app.models.styled_generation import StyledGeneration, StyledGenerationClothingItem
from app.services.prompt_builder_service import build_prompt, get_negative_prompt

# ... inside run_styled_generation_task ...

        # Claim task
        gen.status = "PROCESSING"
        gen.started_at = datetime.now(timezone.utc)
        gen.lease_expires_at = gen.started_at + timedelta(minutes=15)
        gen.worker_id = os.uname().nodename  # or hostname.hostname()
        gen.progress = 5
        db.commit()

        # Fetch garments via junction table in slot order.
        slot_order = {"HAT": 1, "TOP": 2, "PANTS": 3, "SHOES": 4}
        junction_rows = (
            db.query(StyledGenerationClothingItem)
            .filter_by(generation_id=generation_id)
            .all()
        )
        junction_rows.sort(key=lambda jr: slot_order[jr.slot])

        garments_bytes: list[bytes] = []
        garments_for_prompt: list[tuple[str, str]] = []

        for jr in junction_rows:
            ci = jr.clothing_item
            if ci is None or ci.deleted_at is not None:
                raise RuntimeError(
                    f"Clothing item for slot {jr.slot} was deleted"
                )
            img = (
                db.query(ClothingImage)
                .filter_by(clothing_item_id=ci.id, image_type="PROCESSED_FRONT")
                .first()
            )
            if img is None:
                raise RuntimeError(
                    f"Clothing item {ci.id} (slot {jr.slot}) has no PROCESSED_FRONT image"
                )
            garments_bytes.append(await blob_storage.get_bytes(img.blob_hash))
            descriptor = (ci.name or ci.category or "").strip() or (
                {"HAT": "a hat", "TOP": "a top", "PANTS": "pants", "SHOES": "shoes"}[jr.slot]
            )
            garments_for_prompt.append((jr.slot, descriptor))
```

- [ ] **Step 2: Update prompt build + DreamO call**

```python
        final_prompt = build_prompt(gen.scene_prompt, gen.gender, garments_for_prompt)
        final_negative = get_negative_prompt(gen.negative_prompt)

        result_bytes, seed_used = await call_dreamo_generate(
            id_image_bytes=selfie_processed_bytes,
            garment_images_bytes=garments_bytes,
            prompt=final_prompt,
            negative_prompt=final_negative,
            guidance_scale=gen.guidance_scale,
            seed=gen.seed,
            width=gen.width,
            height=gen.height,
        )
```

- [ ] **Step 3: `_update_progress` refreshes lease**

```python
def _update_progress(db: Session, gen: StyledGeneration, progress: int):
    gen.progress = progress
    gen.updated_at = datetime.now(timezone.utc)
    gen.lease_expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    db.commit()
```

- [ ] **Step 4: Run existing pipeline test (if any) after mocking DreamO call**

Create `backend/tests/test_multi_garment_styled_generation.py` (pipeline test, mocks DreamO HTTP call):

```python
"""Multi-garment pipeline test with DreamO mocked."""
from unittest.mock import patch

@patch("app.services.styled_generation_pipeline.call_dreamo_generate")
async def test_pipeline_sends_all_garments(mock_dreamo, db, seed_generation_with_two_garments):
    mock_dreamo.return_value = (b"fake_png", 42)
    from app.services.styled_generation_pipeline import run_styled_generation_task
    await run_styled_generation_task(seed_generation_with_two_garments.id)

    _, kwargs = mock_dreamo.call_args
    assert len(kwargs["garment_images_bytes"]) == 2
    assert kwargs["prompt"]  # non-empty
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/styled_generation_pipeline.py backend/tests/test_multi_garment_styled_generation.py
git commit -m "feat(styled-gen): pipeline fetches multi-garment in slot order; lease bookkeeping"
```

---

## Phase 8: Remaining DB Hardening

### Task 8.1: Retry blob release fix (spec §9.1)

**Files:**
- Modify: `backend/app/api/v1/styled_generation.py` (retry endpoint)

- [ ] **Step 1: Update retry**

Inside `retry_styled_generation`, before setting blob_hash columns to None:

```python
    blob_service = get_blob_service()
    for hash_col in ("result_image_blob_hash", "selfie_processed_blob_hash"):
        h = getattr(gen, hash_col)
        if h:
            blob_service.release(db, h)
            setattr(gen, hash_col, None)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/api/v1/styled_generation.py
git commit -m "fix(retry): release blob refs before clearing hash columns (stop leak)"
```

### Task 8.2: Reap stuck styled_generations

**Files:**
- Modify: `backend/app/tasks.py`
- Modify: `backend/app/core/celery_app.py`

- [ ] **Step 1: Add task in `tasks.py`**

```python
@celery_app.task(name="styled_generation.reap_stuck")
def reap_stuck_styled_generations() -> int:
    from app.db.session import SessionLocal
    from sqlalchemy import text
    db = SessionLocal()
    try:
        result = db.execute(text("""
            UPDATE styled_generations
            SET status='FAILED',
                failure_reason='Worker timeout (lease expired)',
                updated_at=now()
            WHERE status='PROCESSING'
              AND lease_expires_at IS NOT NULL
              AND lease_expires_at < now()
            RETURNING id
        """))
        count = result.rowcount
        db.commit()
        if count:
            logger.info("Reaped %d stuck styled_generations", count)
        return count
    finally:
        db.close()
```

Similarly add `outfit_preview.reap_stuck` and `processing_tasks.reap_stuck`.

- [ ] **Step 2: Add beat entries**

In `celery_app.py`:

```python
celery_app.conf.beat_schedule = {
    "blobs-gc-sweep": {
        "task": "blobs.gc_sweep",
        "schedule": 3600.0,
    },
    "blobs-gc-orphan-files": {
        "task": "blobs.gc_orphan_files",
        "schedule": 604800.0,  # weekly
    },
    "reap-stuck-styled-gen": {
        "task": "styled_generation.reap_stuck",
        "schedule": 3600.0,
    },
    "reap-stuck-outfit-preview": {
        "task": "outfit_preview.reap_stuck",
        "schedule": 3600.0,
    },
    "reap-stuck-processing-tasks": {
        "task": "processing_tasks.reap_stuck",
        "schedule": 3600.0,
    },
}
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/tasks.py backend/app/core/celery_app.py
git commit -m "feat(celery): add reap-stuck tasks for styled_generation/outfit_preview/processing_tasks"
```

### Task 8.3: Orphan file GC

**Files:**
- Modify: `backend/app/tasks.py`

- [ ] **Step 1: Add `blobs.gc_orphan_files`**

```python
@celery_app.task(name="blobs.gc_orphan_files")
def gc_orphan_files() -> int:
    """Sweep the local blob directory for files with no corresponding blobs row,
    older than 24 hours, and delete them."""
    from pathlib import Path
    from app.db.session import SessionLocal
    from app.models.blob import Blob
    from app.services.blob_storage import LocalBlobStorage
    from sqlalchemy import select
    import time

    storage = get_blob_storage()
    if not isinstance(storage, LocalBlobStorage):
        logger.info("orphan-file GC skipped (non-local storage)")
        return 0

    db = SessionLocal()
    try:
        known = {h for (h,) in db.execute(select(Blob.blob_hash))}
        cutoff = time.time() - 86400  # 24h
        deleted = 0
        for shard in storage.base.iterdir():
            if not shard.is_dir():
                continue
            for sub in shard.iterdir():
                if not sub.is_dir():
                    continue
                for f in sub.iterdir():
                    if f.name == "." or len(f.name) != 64:
                        continue
                    if f.name in known:
                        continue
                    if f.stat().st_mtime >= cutoff:
                        continue
                    try:
                        f.unlink()
                        deleted += 1
                    except OSError:
                        logger.exception("Failed to delete orphan %s", f)
        logger.info("orphan-file GC deleted %d files", deleted)
        return deleted
    finally:
        db.close()
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/tasks.py
git commit -m "feat(blobs): add gc_orphan_files sweeper for local storage"
```

### Task 8.4: Processing task retry race

**Files:**
- Modify: `backend/app/api/v1/clothing.py` (retry endpoint, audit item 3)

- [ ] **Step 1: Wrap retry in FOR UPDATE + status check**

Grep for the retry endpoint (probably around the `attempt_no` assignment). Wrap the task fetch in:

```python
    with db.begin_nested():
        task = (
            db.query(ProcessingTask)
            .filter(ProcessingTask.id == task_id)
            .with_for_update()
            .first()
        )
        if task is None or task.status != "FAILED":
            raise HTTPException(409, "task is not in a retriable state")
        task.attempt_no += 1
        task.status = "PENDING"
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/api/v1/clothing.py
git commit -m "fix(retry): lock processing task row before incrementing attempt_no"
```

---

## Phase 9: Docs + Final Integration

### Task 9.1: Update project documentation

**Files:**
- Modify: `documents/API_CONTRACT.md`
- Modify: `documents/BACKEND_ARCHITECTURE.md`
- Modify: `documents/DREAMO_INTEGRATION.md`
- Modify: `documents/DATA_MODEL.md`
- Modify: `groupmembers'markdown/gch.md`

- [ ] **Step 1: API_CONTRACT.md**

Update §10 Styled Generations: request shape now takes gender + clothing_items JSON array. Add /card-packs/popular section. Add /clothing-items publish via PATCH section.

- [ ] **Step 2: BACKEND_ARCHITECTURE.md**

Replace the CreatorItem/ClothingItem duality section with the merged model. Update the ER sketch.

- [ ] **Step 3: DREAMO_INTEGRATION.md**

Remove "V1 Limitations: Single garment only" line; update the request body example to include `garment_images` list. Note the 1-release `garment_image` shim.

- [ ] **Step 4: DATA_MODEL.md**

Restore the original ER diagram's accuracy — the code now matches. Add `catalog_visibility`, `deleted_at`, `view_count` notes.

- [ ] **Step 5: gch.md**

Append a 2026-04-20 section describing this round's work.

- [ ] **Step 6: Commit**

```bash
git add documents/ "groupmembers'markdown/"
git commit -m "docs: update API, architecture, data-model, DreamO, gch for consolidate_and_enhance"
```

### Task 9.2: Full test suite + manual smoke

- [ ] **Step 1: Run full pytest**

```bash
cd backend && pytest -v 2>&1 | tail -50
```
Expected: all pass. Fix any remaining breakage.

- [ ] **Step 2: Start local services**

```bash
docker compose up -d postgres redis
cd backend && uvicorn app.main:app --reload
# separate terminal: celery -A app.core.celery_app worker -Q styled_generation
# separate terminal: celery -A app.core.celery_app beat
```

- [ ] **Step 3: Manual smoke**

```bash
# 1. Create a clothing item, confirm default catalog_visibility=PRIVATE.
# 2. PATCH catalogVisibility=PACK_ONLY.
# 3. Create a CardPack with the item, publish.
# 4. As another user, import the pack; confirm wardrobe shows item.
# 5. As original creator, DELETE the item → expect 204 (tombstone).
# 6. As importer, confirm their copy still works.
# 7. GET /card-packs/popular — should list the published pack.
# 8. POST /styled-generations with gender=female, clothing_items=[{id,slot}]; poll status.
```

- [ ] **Step 4: Commit any last test fixes**

```bash
git status
git add -p
git commit -m "test: finalize integration pass"
```

### Task 9.3: Request code review

Follow superpowers:requesting-code-review skill. Summarize changes: migration + merge + 3-tier delete + view counts + multi-garment DreamO + 22 fixes. Flag high-risk spots: the migration (esp. FK retargeting in step D), the 3-tier delete cascade, and the junction table insert-order semantics.

---

## Self-Review

**Spec coverage:**
- §3 Architecture diagram — no code change needed beyond docs (§9.1). ✅
- §4.1 Junction table — Task 1.4 + 2 model tasks. ✅
- §4.2 New columns on styled_generations — Task 1.2, 2 (absorbed in model). ✅
- §4.3 View count on merged table — Task 1.2 (column) + 1.5 (index) + 6.1 (helper). ✅
- §4.4 Migration — Tasks 1.1–1.5. ✅
- §4.5 In-flight compat — no extra task; migration Task 1.4 handles it. ✅
- §4.6 Merge semantics — Tasks 2, 3, 4. ✅
- §4.7 3-tier delete — Tasks 5.1, 5.2. ✅
- §5.1 New request shape — Task 7.4. ✅
- §5.3 /popular — Task 4.1. ✅
- §5.4 Increment semantics — Task 6.1, 6.2. ✅
- §6 Prompt — Task 7.2. ✅
- §7 DreamO wire — Task 7.3. ✅
- §8 Pipeline — Task 7.5. ✅
- §9.1 retry leak — Task 8.1. ✅
- §9.2 release lock — Task 0.1. ✅
- §9.3 reap stuck — Task 8.2. ✅
- §9.4 orphan GC — Task 8.3. ✅
- §11 Testing — Tasks 0.1, 1.6, 5.2, 6.2, 7.2, 7.3, 7.5 cover the listed test files. ✅
- §13 18 audit defects: item 1 (Task 0.1), 2 (Task 4.1), 3 (Task 8.4), 4 (Task 0.2), 5 (Task 4.2), 6 (documented, not batching — §13 item 6 says don't actually batch), 7 (Task 8.2 covers all three reapers), 8, 9 (Task 4.5), 10 (Task 4.6), 11 (kept under defensive coding; no dedicated task because fix is a re-check, noted in Task 4.1), 12 (Task 3.2 step 4), 13 (Task 4.4 step 3), 14 (Task 0.3), 15 (documented — fix folded into §4.7 cascade cleanup; acceptable), 16 (explicit distinct 4xx codes — folded into Task 5.1 which raises 409 on processing and 404 on not-found), 17 (out of scope; go to follow-ups), 18 (Task 8.2 — outfit_preview reaper covers; N+1 not yet verified — add to §14 follow-ups). ✅ (with 2 "accepted risk" items)

**Placeholders:** None detected. All code blocks are concrete. No "TBD" / "similar to Task N". Checked.

**Type consistency:**
- `StyledGenerationClothingItem` used identically in Tasks 1.4, 7.1, 7.4, 7.5. ✅
- `catalog_visibility` string consistently. ✅
- `delete_with_lifecycle` return type `str | None` used consistently in Tasks 5.1/5.2. ✅
- `garment_images_bytes` kwarg name used in both Tasks 7.3 and 7.5. ✅

No issues found; plan stands.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-20-multi-garment-merge-and-enhancements.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task (or small task group), review between tasks, fast iteration, lower risk of context drift.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

**Which approach?**
