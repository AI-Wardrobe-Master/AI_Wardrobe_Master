# Content-Addressed Storage Refactor & Card Pack Import/Delete Flows

**Status:** Draft — awaiting review
**Author:** gch + Claude
**Date:** 2026-04-15
**Target branch:** `feat/cas-storage-refactor`

---

## 1. Motivation

The AI Wardrobe Master backend currently has three fundamental gaps in how it manages user and creator-owned garment assets:

1. **Duplicated storage, no deduplication.** Every upload is written to a path-based location (`{user_id}/{item_id}/...` or `creators/{creator_id}/{item_id}/...`). If a popular creator item gets imported by 1,000 users, the system would store 1,000 identical copies of the same GLB and PNG bytes.

2. **Card pack import flow does not exist.** `clothing_items.source` has a CHECK constraint `IN ('OWNED', 'IMPORTED')`, but no code path ever writes `'IMPORTED'`. There is no import API, no service, no copy logic. The publish side of card packs is complete; the consume side is vaporware.

3. **Clothing item deletion does not exist.** There is no `DELETE /clothing-items/:id` endpoint. Users cannot remove their own garments from the database. Deletion semantics for imported content vs. owned content have never been addressed.

This spec addresses all three at once because they are structurally coupled: the correct deletion semantics depend on whether storage is shared, and the import flow determines what "shared" means.

---

## 2. Guiding decisions (locked during brainstorming)

These are the product/architecture decisions already agreed with the user, recorded here so implementation does not second-guess them.

| # | Decision | Alternative considered | Why |
|---|---|---|---|
| D1 | **Content-addressed storage (CAS)**: files stored by content hash, deduplicated across all users and creators | Copy-on-import (separate physical files per user) | Storage savings are essential for any popular card pack; deletion semantics fall out of refcounting naturally |
| D2 | **Snapshot-on-import metadata**: when a consumer imports, a new `clothing_items` row is created with copied metadata but shared blob references | Reference-based (thin `clothing_items` view layer over `creator_items`) | Consumer owns their wardrobe rows fully; creator edits never retroactively mutate consumer data; no need to merge the dual-track tables |
| D3 | **SHA-256** as the hash algorithm | BLAKE3 | stdlib, no new dependency; speed difference on 1–5 MB files is microseconds |
| D4 | **Asynchronous GC with 24-hour grace period** | Synchronous delete on `ref_count=0` | Avoids race with concurrent re-uploads of the same content; provides operator recovery window |
| D5 | **URLs never expose hashes**. All file access goes through business routes (`/files/clothing-items/{id}/{kind}`) that internally resolve to blobs | Hash-based paths (`/files/blobs/ab/cd/...`) | Prevents information-leak probing ("does this hash exist?") |
| D6 | **Integer ref_count on `blobs` table**, atomic upsert via `ON CONFLICT` | Application-level locks, trigger-based counting | PostgreSQL native atomicity, visible in Python, no black-magic triggers |
| D7 | **Wipe dev data** on migration; no backfill from existing paths | One-time backfill script that hashes existing files | Pre-production project; complexity of backfill not justified |
| D8 | **Integer whole-pack import**: `POST /imports/card-pack` takes only `card_pack_id`, imports everything | Per-item selection (`item_ids: [...]`) | Simpler API surface; individual items can still be deleted post-import |
| D9 | **Keep creator/consumer dual-track tables**: do not merge `clothing_items` and `creator_items` into one | Unified `items` table with owner relationship | Merging is a separate refactor; out of scope for this change. Blob layer alone solves dedup without touching row structure |
| D10 | **ORM-level refcount release on delete**, not database triggers | PostgreSQL triggers on delete | Explicit, visible to Python debuggers; easy to test; no hidden behavior |

---

## 3. Out of scope

The following are **explicitly not part of this change** and should not be touched:

- Merging `clothing_items` and `creator_items` into a single table
- Multi-garment DreamO generation (still single garment per task)
- DreamO style condition (remains disabled)
- Flutter frontend work (frontend will automatically work once backend URL format is updated; no frontend code changes in this branch)
- Outfit preview business logic (DashScope integration untouched; only its `*_path` columns are migrated to `*_blob_hash`)
- `scripts/init_schema.sql` (raw DDL; legacy, unused by normal flow)
- Hunyuan3D pipeline logic (untouched; only its output-writing code is switched to BlobService)

---

## 4. Data model

### 4.1 New tables

#### `blobs`

Central refcounted registry of all physical file bytes.

```sql
CREATE TABLE blobs (
    blob_hash           CHAR(64) PRIMARY KEY,       -- SHA-256 hex
    byte_size           BIGINT NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    ref_count           INTEGER NOT NULL DEFAULT 0 CHECK (ref_count >= 0),
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_referenced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    pending_delete_at   TIMESTAMPTZ
);
CREATE INDEX idx_blobs_pending_delete
    ON blobs(pending_delete_at)
    WHERE pending_delete_at IS NOT NULL;
```

Semantics:
- `ref_count` is strictly non-negative. CHECK constraint catches bugs.
- `pending_delete_at` is set when `ref_count` transitions to 0, cleared when it goes back to ≥1 ("resurrection"). A blob with `pending_delete_at IS NULL` is live.
- `last_referenced_at` updated on every addref, used for operational diagnostics.
- The index on `pending_delete_at` is partial (only covers rows awaiting GC).

#### `card_pack_imports`

Records the binding "user U imported pack P". Used to decide whether a pack can be hard-deleted and to implement un-import.

```sql
CREATE TABLE card_pack_imports (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_pack_id  UUID NOT NULL REFERENCES card_packs(id) ON DELETE RESTRICT,
    imported_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_card_pack_imports_user_pack UNIQUE (user_id, card_pack_id)
);
CREATE INDEX idx_card_pack_imports_pack ON card_pack_imports(card_pack_id);
```

Semantics:
- `ON DELETE CASCADE` on `user_id`: if a user account is deleted, their import records disappear (and their clothing_items will too via their own cascade, releasing blob refs).
- `ON DELETE RESTRICT` on `card_pack_id`: the database directly refuses to drop a card pack while any import still references it. Business-layer check is a second guard.
- Unique `(user_id, card_pack_id)`: a user cannot import the same pack twice. Re-import requires un-import first.

### 4.2 Modified columns

Twelve path columns switch from `TEXT` (storage path) to `CHAR(64)` (blob hash FK).

| Table | Old column | New column | Nullable |
|---|---|---|---|
| `images` | `storage_path` | `blob_hash` | NOT NULL |
| `creator_item_images` | `storage_path` | `blob_hash` | NOT NULL |
| `models_3d` | `storage_path` | `blob_hash` | NOT NULL |
| `creator_models_3d` | `storage_path` | `blob_hash` | NOT NULL |
| `styled_generations` | `selfie_original_path` | `selfie_original_blob_hash` | NOT NULL |
| `styled_generations` | `selfie_processed_path` | `selfie_processed_blob_hash` | NULL |
| `styled_generations` | `result_image_path` | `result_image_blob_hash` | NULL |
| `outfit_preview_tasks` | `person_image_path` | `person_image_blob_hash` | NOT NULL |
| `outfit_preview_tasks` | `preview_image_path` | `preview_image_blob_hash` | NULL |
| `outfit_preview_task_items` | `garment_image_path` | `garment_image_blob_hash` | NOT NULL |
| `outfits` | `preview_image_path` | `preview_image_blob_hash` | NOT NULL |
| `card_packs` | `cover_image_storage_path` | `cover_image_blob_hash` | NULL |

All new `blob_hash` columns are `CHAR(64)` with a foreign key to `blobs.blob_hash`. Pre-existing uniqueness and check constraints on these tables are preserved unchanged.

**`file_size` columns dropped** from `models_3d` and `creator_models_3d` — this information now lives in `blobs.byte_size`. `vertex_count` / `face_count` are retained (they are 3D mesh semantics, not storage semantics).

### 4.3 Columns added to existing tables

`clothing_items` gets two weak-reference columns to record import lineage:

```sql
ALTER TABLE clothing_items
  ADD COLUMN imported_from_card_pack_id    UUID REFERENCES card_packs(id)    ON DELETE SET NULL,
  ADD COLUMN imported_from_creator_item_id UUID REFERENCES creator_items(id) ON DELETE SET NULL;
CREATE INDEX idx_clothing_items_imported_from_pack
    ON clothing_items(imported_from_card_pack_id);
```

Both are `ON DELETE SET NULL` — if the creator deletes their source material (after imports are gone), the consumer's clothing_items row survives; it only loses the "where did this come from" trail. Data the consumer sees is unaffected because their own metadata is already snapshotted and their blob references are independent.

Both are nullable: owned (`source='OWNED'`) items naturally have both as NULL.

---

## 5. Storage layer

### 5.1 Two-layer split

The existing `StorageService` abstraction is replaced by a two-layer split:

- **`BlobStorage`**: pure byte storage. Knows about filesystem/S3 backends. Knows nothing about the database. Addresses by hash.
- **`BlobService`**: database-backed registry. Manages `blobs` table, refcount, lifecycle. Depends on `BlobStorage`.

Application code (routes, pipelines) uses only `BlobService`.

### 5.2 `BlobStorage` interface

```python
@dataclass
class BlobPutResult:
    blob_hash: str       # SHA-256 hex
    byte_size: int
    mime_type: str

class BlobStorage(Protocol):
    async def put(
        self,
        stream: AsyncIterator[bytes] | BinaryIO,
        *,
        claimed_mime_type: str,
        max_size: int,
    ) -> BlobPutResult:
        """
        Stream-read, hash, and persist bytes. If a blob with this hash
        already exists on the backend, the temporary file is discarded
        and the existing one is reused. Otherwise, atomic rename into place.

        Raises BlobTooLargeError if accumulated size exceeds max_size.
        """

    async def open_stream(self, blob_hash: str) -> AsyncIterator[bytes]:
        """Stream bytes for response delivery. Raises BlobNotFoundError."""

    async def get_bytes(self, blob_hash: str) -> bytes:
        """Load entire blob into memory. For worker use with moderate sizes."""

    async def physical_delete(self, blob_hash: str) -> None:
        """GC-only. Removes the physical bytes. Does not touch the database."""

    def path_for(self, blob_hash: str) -> str:
        """blobs/{hash[:2]}/{hash[2:4]}/{hash}"""
```

Implementations:

- **`LocalBlobStorage`**: writes to `{settings.LOCAL_STORAGE_PATH}/blobs/ab/cd/abcd...`. Upload uses `tempfile.NamedTemporaryFile` in the same filesystem, then `os.replace()` for atomic rename.
- **`S3BlobStorage`**: uses the same path shape as S3 keys. Uploads via `boto3.upload_fileobj`. Existence check via `head_object` before re-uploading.

### 5.3 `BlobService` interface

```python
class BlobService:
    async def ingest_upload(
        self,
        db: Session,
        stream: AsyncIterator[bytes] | BinaryIO,
        *,
        claimed_mime_type: str,
        max_size: int,
    ) -> Blob:
        """
        Full upload flow:
          1. BlobStorage.put() -> (hash, size, mime_type)
          2. Atomic upsert of blobs row:
               INSERT INTO blobs (blob_hash, byte_size, mime_type, ref_count)
               VALUES (:h, :s, :m, 1)
               ON CONFLICT (blob_hash) DO UPDATE
                 SET ref_count = blobs.ref_count + 1,
                     last_referenced_at = now(),
                     pending_delete_at = NULL
          3. Return Blob row (refcount already +1).

        Caller is responsible for committing the transaction.
        """

    def addref(self, db: Session, blob_hash: str) -> None:
        """
        For import flow: bytes already exist. Only increments refcount.
          UPDATE blobs
             SET ref_count = ref_count + 1,
                 last_referenced_at = now(),
                 pending_delete_at = NULL
           WHERE blob_hash = :h
        Raises BlobNotFoundError if hash is unknown.
        """

    def release(self, db: Session, blob_hash: str) -> None:
        """
        For delete flow: decrements refcount. If refcount reaches 0,
        sets pending_delete_at = now(). Does NOT physically delete.
          UPDATE blobs
             SET ref_count = ref_count - 1,
                 pending_delete_at = CASE
                    WHEN ref_count - 1 = 0 THEN now()
                    ELSE pending_delete_at
                 END
           WHERE blob_hash = :h
        """
```

All three operations are called from within open transactions; the caller commits. This matters for consistency: blob refcount and the referencing business row must change together.

### 5.4 Physical layout

Local filesystem:
```
backend_storage/
└── blobs/
    ├── ab/
    │   ├── cd/
    │   │   └── abcd012345...ef   (full SHA-256 hex)
    │   └── ef/
    └── ...
```

Two-level directory sharding (256 × 256 = 65,536 directories max) keeps any single directory at manageable size even with millions of blobs.

S3 uses the same key structure.

### 5.5 Upload size and hashing

The `ingest_upload` flow is strictly streaming:

```python
hasher = hashlib.sha256()
temp = tempfile.NamedTemporaryFile(delete=False, dir=settings.LOCAL_STORAGE_PATH)
size = 0
try:
    async for chunk in stream:
        size += len(chunk)
        if size > max_size:
            raise BlobTooLargeError(size, max_size)
        hasher.update(chunk)
        temp.write(chunk)
    temp.close()
    blob_hash = hasher.hexdigest()
    final_path = blob_storage.path_for(blob_hash)
    if not exists(final_path):
        os.replace(temp.name, final_path)
    else:
        os.unlink(temp.name)
finally:
    if os.path.exists(temp.name):
        os.unlink(temp.name)
```

Never load entire files into memory. Temp file lives in the same filesystem as the final destination so `os.replace` is atomic.

---

## 6. Business flows

### 6.1 Write path (upload + processing)

**`POST /clothing-items`** (existing endpoint, body unchanged):

```python
@router.post("", status_code=202)
async def create_clothing_item(
    front_image: UploadFile, back_image: UploadFile | None, ...
):
    item = ClothingItem(..., source="OWNED")
    db.add(item); db.flush()

    front_blob = await blob_service.ingest_upload(
        db, front_image.file,
        claimed_mime_type=front_image.content_type,
        max_size=settings.MAX_UPLOAD_SIZE_BYTES,
    )
    db.add(Image(
        clothing_item_id=item.id,
        image_type="ORIGINAL_FRONT",
        blob_hash=front_blob.blob_hash,
    ))
    # ... same for back_image if present
    # ... create processing task, enqueue celery
    db.commit()
```

**`clothing_pipeline.run_pipeline_task`** (Celery worker):

```python
# Read original bytes for processing
original_bytes = await blob_storage.get_bytes(original_image.blob_hash)

# Background removal
processed_bytes = await remove_background(original_bytes)
processed_blob = await blob_service.ingest_upload(
    db, io.BytesIO(processed_bytes),
    claimed_mime_type="image/png",
    max_size=settings.MAX_UPLOAD_SIZE_BYTES * 2,  # processed can be larger
)
db.add(Image(
    clothing_item_id=item_id,
    image_type="PROCESSED_FRONT",
    blob_hash=processed_blob.blob_hash,
))

# ... same pattern for 3D model, 8 angle views
```

`styled_generation_pipeline` and `outfit_preview` pipelines follow the same pattern.

### 6.2 Read path (URL delivery)

Drop `app.mount("/files", StaticFiles(...))`. Replace with a business router:

```python
# backend/app/api/v1/files.py

IMAGE_KIND_MAP = {
    "original-front": ("ORIGINAL_FRONT", None),
    "original-back": ("ORIGINAL_BACK", None),
    "processed-front": ("PROCESSED_FRONT", None),
    "processed-back": ("PROCESSED_BACK", None),
    "angle-0": ("ANGLE_VIEW", 0),
    "angle-45": ("ANGLE_VIEW", 45),
    # ...
    "angle-315": ("ANGLE_VIEW", 315),
}

@router.get("/clothing-items/{item_id}/{kind}")
async def get_clothing_image(
    item_id: UUID,
    kind: str,
    user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404)

    if kind == "model":
        model = db.query(Model3D).filter_by(clothing_item_id=item_id).first()
        if not model:
            raise HTTPException(404)
        return StreamingResponse(
            blob_storage.open_stream(model.blob_hash),
            media_type="model/gltf-binary",
        )

    if kind not in IMAGE_KIND_MAP:
        raise HTTPException(404)
    image_type, angle = IMAGE_KIND_MAP[kind]
    img_row = db.query(Image).filter_by(
        clothing_item_id=item_id,
        image_type=image_type,
        angle=angle,
    ).first()
    if not img_row:
        raise HTTPException(404)
    blob = db.query(Blob).filter_by(blob_hash=img_row.blob_hash).first()
    return StreamingResponse(
        blob_storage.open_stream(img_row.blob_hash),
        media_type=blob.mime_type,
    )
```

Additional routes:
- `GET /files/styled-generations/{gen_id}/{kind}` — for selfie-original / selfie-processed / result
- `GET /files/outfits/{outfit_id}/preview` — for outfit preview
- `GET /files/card-packs/{pack_id}/cover` — for pack covers (public if pack is PUBLISHED)
- `GET /files/creator-items/{item_id}/{kind}` — creator-side (creator-auth)

For S3 backend, these routes return `RedirectResponse(...presigned_url...)` instead of streaming. The presigned URL expires in one hour.

Existing response schemas (`ClothingItemResponse`, etc.) gain an updated `_to_response` helper that builds these business URLs:

```python
def clothing_image_url(item_id, kind) -> str:
    return f"{settings.API_V1_STR}/files/clothing-items/{item_id}/{kind}"
```

The frontend sees URLs like `/api/v1/files/clothing-items/abc-123/processed-front`. It does not see hashes.

### 6.3 Delete path — `clothing_item`

New endpoint `DELETE /clothing-items/:id`:

```python
@router.delete("/{item_id}", status_code=204)
def delete_clothing_item(
    item_id: UUID,
    user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404)

    # Block delete if an active processing task exists
    active = db.query(ProcessingTask).filter(
        ProcessingTask.clothing_item_id == item_id,
        ProcessingTask.status.in_(["PENDING", "PROCESSING"]),
    ).first()
    if active:
        raise HTTPException(409, "Cannot delete while processing")

    # Collect blob hashes to release before cascade
    blob_hashes = [img.blob_hash for img in item.images]
    if item.model_3d:
        blob_hashes.append(item.model_3d.blob_hash)

    db.delete(item)   # CASCADE deletes images, models_3d, processing_tasks, wardrobe_items
    db.flush()

    for h in blob_hashes:
        blob_service.release(db, h)

    db.commit()
```

This path handles both OWNED and IMPORTED clothing_items uniformly. The difference between them is only in metadata origin; the delete semantics are identical.

Wardrobe_items, outfit_items, outfit_preview_task_items that reference this clothing_item will be cascade-deleted by existing FK constraints. No new coupling introduced.

**Open edge case:** what if an outfit_preview_task is currently running and references this clothing_item? The task's `outfit_preview_task_items.clothing_item_id` has `ON DELETE CASCADE`, so the row would be deleted mid-task. The 409 guard above only checks the item's own `processing_tasks`, not outfit_preview_tasks. **Resolution:** accept this as a minor known limitation — outfit preview tasks are short-lived (< 30s) and the chance of a delete racing with them is minimal. The task would fail gracefully when it tries to fetch the removed row; it already has a FAILED status handler.

### 6.4 Delete path — `creator_item`

The existing rule is preserved: creator cannot delete a `creator_item` while it belongs to a PUBLISHED `card_pack`. Rationale: published packs must remain importable by new users.

When `creator_item` delete is allowed:

```python
def delete_creator_item(db, item_id, creator_id):
    item = crud_creator_items.get_own(db, item_id, creator_id)
    if not item:
        raise HTTPException(404)

    # Existing check: item in published pack
    in_published = db.query(CardPackItem).join(CardPack).filter(
        CardPackItem.creator_item_id == item_id,
        CardPack.status == "PUBLISHED",
    ).first()
    if in_published:
        raise HTTPException(409, "Remove from published card packs first")

    blob_hashes = [img.blob_hash for img in item.images]
    if item.model_3d:
        blob_hashes.append(item.model_3d.blob_hash)

    db.delete(item)
    db.flush()
    for h in blob_hashes:
        blob_service.release(db, h)
    db.commit()
```

Important: releasing the creator-side blobs does not harm any imported consumer rows, because each consumer row already added its own addref during import. The refcount only drops by 1 per creator image/model row, not by the total across all consumers.

### 6.5 Delete / Archive path — `card_pack`

Archive is unconditional; hard delete requires no active imports.

```python
@router.post("/{pack_id}/archive", status_code=200)
def archive_card_pack(pack_id, creator_id, db):
    pack = crud_card_pack.get_own(db, pack_id, creator_id)
    if not pack:
        raise HTTPException(404)
    if pack.status == "ARCHIVED":
        return _to_response(pack)
    pack.status = "ARCHIVED"
    pack.archived_at = datetime.now(timezone.utc)
    db.commit()
    return _to_response(pack)

@router.delete("/{pack_id}", status_code=204)
def delete_card_pack(pack_id, creator_id, db):
    pack = crud_card_pack.get_own(db, pack_id, creator_id)
    if not pack:
        raise HTTPException(404)

    if pack.status == "PUBLISHED":
        raise HTTPException(409, "Published packs must be archived before deletion")

    import_count = db.query(CardPackImport).filter_by(card_pack_id=pack_id).count()
    if import_count > 0:
        raise HTTPException(
            409,
            f"{import_count} user(s) have imported this pack. "
            "Delete is blocked until all imports are removed."
        )

    blob_hashes = []
    if pack.cover_image_blob_hash:
        blob_hashes.append(pack.cover_image_blob_hash)

    db.delete(pack)   # CASCADE deletes card_pack_items
    db.flush()
    for h in blob_hashes:
        blob_service.release(db, h)
    db.commit()
```

Semantics:
- DRAFT pack: can be archived (no-op, rare) or deleted freely.
- PUBLISHED pack with no imports: must be archived first, then deleted. This is a two-step to prevent accidental destruction.
- PUBLISHED or ARCHIVED pack with active imports: HARD delete is blocked. Archive is always a valid fallback.

Note: a PUBLISHED pack can be archived even with imports. Archive just hides it from discovery; existing imports continue working indefinitely because they have independent snapshots.

### 6.6 Import path — card pack

New router `backend/app/api/v1/imports.py`:

```python
@router.post("/card-pack", status_code=201)
async def import_card_pack(
    body: ImportCardPackRequest,  # {card_pack_id: UUID}
    user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    pack = (
        db.query(CardPack)
        .filter(CardPack.id == body.card_pack_id, CardPack.status == "PUBLISHED")
        .first()
    )
    if not pack:
        raise HTTPException(404, "Pack not found or not published")

    # Idempotence: one record per (user, pack)
    existing = db.query(CardPackImport).filter_by(
        user_id=user_id, card_pack_id=pack.id,
    ).first()
    if existing:
        raise HTTPException(409, "Pack already imported")

    db.add(CardPackImport(user_id=user_id, card_pack_id=pack.id))

    imported_item_ids = []
    pack_items = (
        db.query(CardPackItem)
        .filter(CardPackItem.card_pack_id == pack.id)
        .order_by(CardPackItem.sort_order)
        .all()
    )

    for pi in pack_items:
        ci = pi.creator_item

        # 1. Snapshot metadata into new clothing_items row
        clothing_item = ClothingItem(
            user_id=user_id,
            source="IMPORTED",
            name=ci.name,
            description=ci.description,
            predicted_tags=list(ci.predicted_tags),
            final_tags=list(ci.final_tags),
            is_confirmed=True,
            custom_tags=[],
            imported_from_card_pack_id=pack.id,
            imported_from_creator_item_id=ci.id,
        )
        db.add(clothing_item)
        db.flush()

        # 2. Reference creator's blobs for every image row
        for ci_img in ci.images:
            db.add(Image(
                clothing_item_id=clothing_item.id,
                image_type=ci_img.image_type,
                angle=ci_img.angle,
                blob_hash=ci_img.blob_hash,
            ))
            blob_service.addref(db, ci_img.blob_hash)

        # 3. Reference creator's 3D model
        if ci.model_3d:
            db.add(Model3D(
                clothing_item_id=clothing_item.id,
                model_format=ci.model_3d.model_format,
                blob_hash=ci.model_3d.blob_hash,
                vertex_count=ci.model_3d.vertex_count,
                face_count=ci.model_3d.face_count,
            ))
            blob_service.addref(db, ci.model_3d.blob_hash)

        imported_item_ids.append(clothing_item.id)

    pack.import_count += 1
    db.commit()

    return {
        "cardPackId": str(pack.id),
        "importedItemIds": [str(i) for i in imported_item_ids],
    }
```

The imported clothing_items end up in the user's default wardrobe via the same mechanism as OWNED items (or, if a "virtual wardrobe" convention exists, into that one — to be confirmed during implementation).

### 6.7 Un-import path

```python
@router.delete("/card-pack/{pack_id}", status_code=204)
def unimport_card_pack(
    pack_id: UUID,
    user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    record = db.query(CardPackImport).filter_by(
        user_id=user_id, card_pack_id=pack_id,
    ).first()
    if not record:
        raise HTTPException(404, "Not imported")

    # Find all clothing_items originating from this pack for this user
    items = db.query(ClothingItem).filter(
        ClothingItem.user_id == user_id,
        ClothingItem.imported_from_card_pack_id == pack_id,
    ).all()

    for item in items:
        # Reuse the delete helper, which handles blob release
        _delete_clothing_item_internal(db, item)

    db.delete(record)

    pack = db.query(CardPack).filter_by(id=pack_id).first()
    if pack and pack.import_count > 0:
        pack.import_count -= 1

    db.commit()
```

---

## 7. Garbage collection

### 7.1 Celery Beat schedule

New periodic task in `backend/app/tasks.py`:

```python
@celery_app.task(name="blobs.gc_sweep")
def gc_sweep():
    db = SessionLocal()
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
        candidates = db.query(Blob).filter(
            Blob.pending_delete_at.isnot(None),
            Blob.pending_delete_at < cutoff,
            Blob.ref_count == 0,
        ).limit(1000).all()

        for blob in candidates:
            try:
                asyncio.run(blob_storage.physical_delete(blob.blob_hash))
            except FileNotFoundError:
                logger.warning("Blob %s already missing", blob.blob_hash)
            except Exception:
                logger.exception("GC failed for %s", blob.blob_hash)
                continue
            db.delete(blob)

        db.commit()
    finally:
        db.close()
```

Beat schedule in `celery_app.py`:

```python
from celery.schedules import crontab

celery_app.conf.beat_schedule = {
    "blob-gc-sweep": {
        "task": "blobs.gc_sweep",
        "schedule": crontab(minute=17),
    },
}
```

(`:17` instead of `:00` to spread load if multiple teams run similar jobs on shared infrastructure.)

### 7.2 Celery Beat service

Add a new Docker compose service `celery-beat`:

```yaml
celery-beat:
  build:
    context: ./backend
    dockerfile: Dockerfile
  depends_on:
    db: { condition: service_healthy }
    redis: { condition: service_healthy }
  command: celery -A app.core.celery_app beat --loglevel=info
  environment:
    # same as celery-styled-gen worker
    ...
  volumes:
    - backend_storage:/app/storage
```

Only one `celery-beat` instance should run across the cluster. For local dev this is trivially satisfied.

### 7.3 Reconciliation script

A defensive operational tool at `backend/scripts/verify_blob_refcount.py`:

```python
"""
Scan all business tables, sum actual references per blob_hash,
compare against blobs.ref_count, report discrepancies.

Does NOT auto-correct. Intended for manual diagnosis.
"""

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
```

Not called by any production code path. Manually invokable via `python -m scripts.verify_blob_refcount`.

---

## 8. Migration strategy

### 8.1 Single monolithic Alembic migration

Because dev data is being wiped, there is no need to migrate existing data row-by-row. A single migration performs the schema transformation.

File: `backend/alembic/versions/20260415_000010_cas_storage_refactor.py`

```python
revision = "20260415_000010"
down_revision = "20260413_000005"

def upgrade():
    # 1. New tables
    op.create_table("blobs", ...)
    op.create_table("card_pack_imports", ...)

    # 2. clothing_items: add imported_from columns
    op.add_column("clothing_items",
        sa.Column("imported_from_card_pack_id", UUID, nullable=True))
    op.add_column("clothing_items",
        sa.Column("imported_from_creator_item_id", UUID, nullable=True))
    op.create_foreign_key(None, "clothing_items", "card_packs",
        ["imported_from_card_pack_id"], ["id"], ondelete="SET NULL")
    op.create_foreign_key(None, "clothing_items", "creator_items",
        ["imported_from_creator_item_id"], ["id"], ondelete="SET NULL")

    # 3. Twelve column swaps
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
        op.add_column(table,
            sa.Column(new_col, sa.CHAR(64),
                sa.ForeignKey("blobs.blob_hash"),
                nullable=nullable))

    # 4. Drop redundant file_size columns on model tables
    op.drop_column("models_3d", "file_size")
    op.drop_column("creator_models_3d", "file_size")

def downgrade():
    # Restore columns (as TEXT), drop new tables, remove FK.
    # Not a clean round-trip — dev data is lost regardless.
    ...
```

### 8.2 Developer operational steps

On fresh pull:

```bash
docker compose down -v              # wipe postgres + backend_storage volumes
docker compose up --build           # rebuild, start everything
# backend container runs alembic upgrade head on startup
# demo user gets recreated
```

For clean re-runs mid-development, the same command works.

### 8.3 Revision numbering

The new migration is `20260415_000010`, chaining onto `20260413_000005`. This continues the global sequential counter that the rest of the project uses (000001 through 000009 already exist).

---

## 9. Files changed

### 9.1 New files (estimated 10)

| Path | Purpose |
|---|---|
| `backend/app/models/blob.py` | `Blob` SQLAlchemy model |
| `backend/app/models/card_pack_import.py` | `CardPackImport` model (or add to `creator.py`) |
| `backend/app/services/blob_storage.py` | `BlobStorage` protocol + `LocalBlobStorage` + `S3BlobStorage` |
| `backend/app/services/blob_service.py` | `BlobService` (refcount management) |
| `backend/app/services/import_service.py` | Card pack import business logic |
| `backend/app/api/v1/files.py` | Business-path file serving router |
| `backend/app/api/v1/imports.py` | Import / un-import endpoints |
| `backend/alembic/versions/20260415_000010_cas_storage_refactor.py` | Migration |
| `backend/scripts/verify_blob_refcount.py` | Reconciliation tool |
| `docs/superpowers/specs/2026-04-15-cas-storage-refactor-design.md` | This spec |

### 9.2 Modified files (estimated 12)

| Path | Change |
|---|---|
| `backend/app/services/storage_service.py` | Deprecated; kept as thin compatibility shim during transition or removed entirely |
| `backend/app/services/clothing_pipeline.py` | All `storage.upload()` → `blob_service.ingest_upload()`; reads via `blob_storage.get_bytes()` |
| `backend/app/services/styled_generation_pipeline.py` | Same pattern |
| `backend/app/services/background_removal_service.py` | No change (already takes/returns bytes) |
| `backend/app/main.py` | Remove `/files` static mount |
| `backend/app/api/v1/router.py` | Include `files`, `imports` routers |
| `backend/app/api/v1/clothing.py` | `POST` uses `blob_service`; new `DELETE /clothing-items/:id`; URL construction uses business paths |
| `backend/app/api/v1/creator_items.py` | Same pattern; existing delete check retained |
| `backend/app/api/v1/card_packs.py` | New `POST /archive` endpoint; `DELETE` logic updated per §6.5 |
| `backend/app/api/v1/styled_generation.py` | `blob_service` for uploads; URL construction |
| `backend/app/models/clothing_item.py` | `Image`, `Model3D` field rename; add `imported_from_*` to `ClothingItem` |
| `backend/app/models/creator.py` | `CreatorItemImage`, `CreatorItemModel3D`, `CardPack` field rename |
| `backend/app/models/styled_generation.py` | Field rename |
| `backend/app/models/outfit_preview.py` | Field rename |
| `backend/app/core/celery_app.py` | Add `beat_schedule` |
| `backend/app/tasks.py` | Add `gc_sweep` task |
| `docker-compose.yml` | Add `celery-beat` service |
| `backend/app/models/__init__.py` | Export new models |
| `backend/alembic/env.py` | Import new models for metadata |
| `documents/BACKEND_ARCHITECTURE.md` | Describe CAS layer |
| `documents/API_CONTRACT.md` | Add import/unimport/delete endpoints |

---

## 10. Acceptance criteria

An implementation of this spec is considered complete when all of the following pass manually:

1. **Fresh migration succeeds.** On a wiped database, `alembic upgrade head` runs to completion; all 19 expected tables exist; `alembic heads` reports a single head.

2. **Owned item round-trip.** `POST /clothing-items` with a front+back image → Celery pipeline runs → `GET /files/clothing-items/:id/processed-front` returns bytes → `GET /clothing-items/:id/model` returns a valid GLB. Both front and back images, all 8 angle views, and the model file exist.

3. **Dedup verification.** Upload the same image bytes for two different clothing items under two different users. `SELECT COUNT(*) FROM blobs` for the relevant hash returns 1 row with `ref_count = 2`.

4. **Delete own item.** `DELETE /clothing-items/:id` on an owned item: row and all descendant images/model rows removed; blob `ref_count` decrements; on a unique blob it reaches 0 and `pending_delete_at` is set; after 24 hours the GC task removes the physical file.

5. **Card pack publish → import.** Creator creates `creator_item`, builds a card pack, publishes. Another user calls `POST /imports/card-pack` → receives `importedItemIds` → those items appear in their wardrobe with `source='IMPORTED'` → the underlying blobs have refcount >= 2 (creator + one consumer).

6. **Consumer edits imported metadata.** Consumer updates `final_tags` on an imported item → creator's original unchanged. Verifiable via direct DB query.

7. **Creator delete blocked while in published pack.** Creator tries `DELETE /creator-items/:id` on an item whose pack is PUBLISHED → 409. Creator archives the pack → delete now succeeds. No consumer imported the pack.

8. **Card pack hard delete blocked by imports.** Creator tries `DELETE /card-packs/:id` on a pack that has an active `card_pack_imports` row → 409 with `import_count`. User un-imports → creator's delete now succeeds.

9. **Un-import.** `DELETE /imports/card-pack/:id` removes the `card_pack_imports` row and all clothing_items that originated from that pack; decrements blob refcounts; does not affect other imported packs from the same user.

10. **No existing flow regresses.** The original Hunyuan3D clothing pipeline still produces full front/back/model/angles via the same user-facing API (only URL format changes). DreamO styled_generation flow still works end-to-end. Outfit preview (DashScope) integration still uploads person/garment images and retrieves results.

11. **URL privacy.** No API response, no log line, no redirect URL contains a raw blob hash in its path or query string (except S3 presigned URLs, which are short-lived tokens, not structural paths).

12. **GC correctness.** Manually insert a blob with `ref_count=0` and `pending_delete_at` in the past; run `gc_sweep` task; verify physical file is removed and `blobs` row is gone.

---

## 11. Known limitations

- **No backfill for existing deployments.** If this spec is shipped after any real user data exists, it will destroy that data. The nuke-and-rebuild assumption is only valid for pre-production.
- **S3 physical delete is not strongly consistent.** After `physical_delete`, S3 may still serve the object for a few seconds (read-after-delete eventual consistency on some configurations). Impact is negligible because any live consumer would be blocked by refcount > 0 anyway.
- **Concurrent ingest of the same hash has a small race window.** If two workers simultaneously upload identical bytes and both check existence before either writes, both may write. The `os.replace` is atomic so only the second write wins, but the first writer's temporary file stays until cleanup in the `finally` block. Minor disk churn, no correctness issue.
- **The clothing_item delete endpoint does not check outfit_preview_tasks.** If an item is referenced by an in-flight outfit preview job, deleting it will cascade the `outfit_preview_task_items` row and the worker will see it disappear. Documented in §6.3 as acceptable.
- **No undo for user deletes.** Once `DELETE /clothing-items/:id` commits and GC eventually runs, the content is gone. No soft-delete tier.

---

## 12. References

- Brainstorming session transcript (2026-04-15 chat)
- Current database exploration report (2026-04-15 chat, section "当前数据库现状报告")
- Alembic migration chain fix: commit `d05cc42`
