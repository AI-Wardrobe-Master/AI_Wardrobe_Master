# Multi-Garment DreamO + Database Hardening + View Counts — Design

**Date:** 2026-04-20
**Owner:** gch (backend)
**Status:** Draft for review

---

## 1. Motivation

Three related backend improvements:

1. **Multi-garment styled generation.** Today `POST /styled-generations` only accepts one clothing item. DreamO's native `pre_condition` already supports a list of reference images with mixed tasks (`id`, `ip`, `style`), but our server wrapper, HTTP client, pipeline, DB model, and prompt builder all hard-code a single garment. We need face + gender + 1–4 garments (one per slot: `HAT`/`TOP`/`PANTS`/`SHOES`) + scene prompt → composed prompt → single generated portrait.
2. **Database correctness fixes.** Four concrete defects in the existing CAS + styled-generation code (blob leak on retry, missing advisory lock in `release()`, no lease reaper for stuck styled generations, orphan physical files on rollback).
3. **Platform view counts & popular card packs.** Creators' published items and card packs need a view counter so the app can surface the top 10 most-viewed packs on the discovery screen instead of listing everything.

---

## 2. Scope

In scope:
- `DreamO/server.py` — accept multiple garment images.
- `backend/app/services/dreamo_client_service.py` — send list of garment bytes.
- `backend/app/services/prompt_builder_service.py` — build gender-aware, multi-garment prompt.
- `backend/app/services/styled_generation_pipeline.py` — fetch multiple garments, populate new lease fields.
- `backend/app/models/styled_generation.py` + new association model — add `gender`, lease fields, junction table.
- `backend/app/api/v1/styled_generation.py` + schemas — new request shape.
- `backend/app/services/blob_service.py` — advisory lock in `release()`.
- `backend/app/tasks.py` — reap-stuck task, orphan file GC, increment view count helper.
- `backend/app/models/creator.py` — `view_count` column on `creator_items` and `card_packs`.
- `backend/app/api/v1/creator_items.py`, `backend/app/api/v1/card_packs.py` — increment on detail GET, new `/card-packs/popular` endpoint.
- New Alembic migration `20260420_000015_multi_garment_gender_view_counts.py`.

Out of scope:
- Flutter changes (the frontend owner adapts separately; we will keep the old `clothing_item_id` field accepted for one release as a transitional shim — see §5.1).
- Personalized recommendations beyond a raw top-N-by-views list.
- View counts on private `clothing_items`.

---

## 3. Architecture Impact

No new services. Existing wire:

```
Flutter  --multipart-->  FastAPI /styled-generations
                            |
                            v (Celery styled_generation queue)
                     styled_generation_pipeline
                            |
                            v (HTTP)
                     DreamO service /generate
```

Changes are internal to the pipeline; DreamO service gains a new optional field, but request flow is unchanged.

---

## 4. Data Model

### 4.1 New table: `styled_generation_clothing_items`

Junction between a styled generation and the clothing items it references, with slot typing.

```python
class StyledGenerationClothingItem(Base):
    __tablename__ = "styled_generation_clothing_items"

    id               = Column(UUID, primary_key=True, default=uuid4)
    generation_id    = Column(UUID, ForeignKey("styled_generations.id", ondelete="CASCADE"),
                              nullable=False, index=True)
    clothing_item_id = Column(UUID, ForeignKey("clothing_items.id", ondelete="CASCADE"),
                              nullable=False, index=True)
    slot             = Column(String(10), nullable=False)   # HAT|TOP|PANTS|SHOES
    position         = Column(Integer, nullable=False, default=0)
    created_at       = Column(DateTime(timezone=True), default=utcnow)

    __table_args__ = (
        CheckConstraint("slot IN ('HAT','TOP','PANTS','SHOES')", name="ck_sgci_slot"),
        UniqueConstraint("generation_id", "slot", name="uq_sgci_gen_slot"),
    )
```

Rationale:
- `ondelete="CASCADE"` on `clothing_item_id`: if a user deletes a clothing item they own, the junction rows pointing at it go away. The parent `StyledGeneration` row still exists with its result image intact (user's generation history is not destroyed), but subsequent retry will fail with "no garments" — same semantics as the existing `source_clothing_item_id` FK's `SET NULL` behavior, just cleaner.
- Unique `(generation_id, slot)` means a single generation can have at most one item per slot, i.e. max 4 garments total. If the frontend later wants multiple pieces in the same slot (e.g. jacket + t-shirt), we'd drop this constraint — out of scope today.

### 4.2 `styled_generations` — new columns

| Column                | Type         | Null | Default | Notes |
|-----------------------|--------------|------|---------|-------|
| `gender`              | `VARCHAR(10)`| NO   | –       | CHECK in `('MALE','FEMALE')`. Added as NOT NULL with a one-time backfill default of `'FEMALE'` (see §4.4) for existing rows, then NOT NULL is enforced. |
| `started_at`          | `TIMESTAMPTZ`| YES  | NULL    | Set when status transitions PENDING → PROCESSING. |
| `lease_expires_at`    | `TIMESTAMPTZ`| YES  | NULL    | Extended on each `_update_progress`; reaper fails stale leases. |
| `worker_id`           | `VARCHAR(255)`| YES | NULL    | Mirrors `processing_tasks.worker_id` for debuggability. |

`source_clothing_item_id` is retained (as user requested) but is treated as a deprecated, redundant pointer to the `TOP` row in the junction table. Reads ignore it; writes only update it when the new pipeline inserts the first TOP-slot row (for dashboard queries that may still use it).

### 4.3 `creator_items` and `card_packs` — view count

```sql
ALTER TABLE creator_items ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_packs    ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0;

CREATE INDEX idx_creator_items_view_count  ON creator_items (view_count DESC);
CREATE INDEX idx_card_packs_popular
    ON card_packs (view_count DESC, created_at DESC)
    WHERE status = 'PUBLISHED';
```

`clothing_items` gets no change — private user wardrobe items are not counted, per requirement.

### 4.4 Alembic migration: `20260420_000015_multi_garment_gender_view_counts.py`

Revises: `20260420_000014_link_card_packs_to_public_wardrobes`.

Upgrade steps, in order:

1. Create `styled_generation_clothing_items` (schema above).
2. Backfill: for every existing `styled_generations` row with a non-NULL `source_clothing_item_id`, insert a junction row `(generation_id=sg.id, clothing_item_id=sg.source_clothing_item_id, slot='TOP', position=0)`.
3. Add `gender` NULLABLE with no default, run `UPDATE styled_generations SET gender='FEMALE' WHERE gender IS NULL`, then `ALTER COLUMN ... SET NOT NULL` and add the CHECK constraint. (`'FEMALE'` is arbitrary; we have no better signal for legacy rows. In-flight PENDING/PROCESSING rows keep running — see §4.5.)
4. Add `started_at`, `lease_expires_at`, `worker_id` (all nullable).
5. Add `view_count` NOT NULL DEFAULT 0 to `creator_items` and `card_packs`, plus the two indexes.

Downgrade reverses: drop view_count indexes + columns, drop lease columns, drop gender constraint+column, drop junction table.

### 4.5 In-flight task compatibility

Before running the pipeline change, existing `PENDING`/`PROCESSING` rows would have no junction rows — but the migration's backfill step inserts one per row, so the new pipeline's query `SELECT ... FROM styled_generation_clothing_items WHERE generation_id=?` returns exactly one `TOP`-slot entry. Legacy tasks therefore continue to produce a single-garment result using the new code path. Gender defaults to `'FEMALE'` — acceptable because (a) the old prompt template didn't use gender anyway, so fidelity is not regressing, and (b) the user can delete & retry if unhappy.

---

## 5. API

### 5.1 `POST /api/v1/styled-generations` — new request shape

multipart/form-data:

| Field              | Type                | Req | Notes |
|--------------------|---------------------|-----|-------|
| `selfie_image`     | file                | yes | ≤10 MB |
| `gender`           | string              | yes | `"male"` or `"female"` (case-insensitive) |
| `scene_prompt`     | string              | yes | non-empty |
| `clothing_items`   | string (JSON)       | yes | JSON array, 1–4 items: `[{"id":"<uuid>","slot":"HAT|TOP|PANTS|SHOES"}]`. Slots must be unique. |
| `negative_prompt`  | string              | no  | |
| `guidance_scale`   | float               | no  | default 4.5, range 1–10 |
| `seed`             | int                 | no  | default -1 |
| `width`, `height`  | int                 | no  | defaults 1024, range 768–1024 |

Legacy transitional shim: if `clothing_item_id` (old single field) is provided and `clothing_items` is not, backend synthesizes `[{"id":<id>,"slot":"TOP"}]` internally. One release only; emit a deprecation header.

Validation errors (422) — specific messages:
- `"clothing_items must be a JSON array of 1 to 4 items"`
- `"duplicate slot <SLOT> in clothing_items"`
- `"unknown slot <X> (must be HAT|TOP|PANTS|SHOES)"`
- `"gender must be 'male' or 'female'"`

Business error (409) — unchanged semantics: any referenced garment without a `PROCESSED_FRONT` image returns `"Clothing item <id> (slot <SLOT>) has not finished processing"`.

### 5.2 Response — `StyledGenerationResponse` additions

```json
{
  ...existing fields...,
  "gender": "male",
  "garments": [
    {"id": "<uuid>", "slot": "HAT",   "name": "Red Baseball Cap", "imageUrl": "/files/clothing-items/<uuid>/processed-front"},
    {"id": "<uuid>", "slot": "TOP",   "name": "Blue Denim Jacket", "imageUrl": "..."},
    {"id": "<uuid>", "slot": "PANTS", "name": "Dark Jeans", "imageUrl": "..."}
  ]
}
```

`sourceClothingItemId` remains for backward compat but is documented as deprecated.

### 5.3 `GET /api/v1/card-packs/popular`

```
GET /api/v1/card-packs/popular?limit=10
```

- Auth: optional (same as `GET /card-packs/share/...`). Public discovery.
- `limit`: int, default 10, max 50.
- Filter: `status='PUBLISHED'`.
- Order: `view_count DESC, created_at DESC`.
- Response: identical structure to `GET /card-packs` list response, so the Flutter list widgets reuse the same parser.

### 5.4 View-count increment semantics

Apply to these endpoints:

| Endpoint                                    | Target table    | Increment condition |
|---------------------------------------------|-----------------|---------------------|
| `GET /api/v1/creator-items/{item_id}`       | `creator_items` | `catalog_visibility != 'PRIVATE'` AND (not authenticated OR `viewer_user_id != creator_id`) |
| `GET /api/v1/card-packs/{pack_id}`          | `card_packs`    | `status = 'PUBLISHED'` AND (not authenticated OR `viewer_user_id != creator_id`) |
| `GET /api/v1/card-packs/share/{share_id}`   | `card_packs`    | `status = 'PUBLISHED'` AND (not authenticated OR `viewer_user_id != creator_id`) |

Increment statement (atomic — avoids the read-modify-write race that would otherwise happen under concurrency):

```python
db.query(Model).filter(Model.id == target_id).update(
    {Model.view_count: Model.view_count + 1},
    synchronize_session=False,
)
db.commit()
```

The increment runs **after** the GET's normal response is composed (i.e. the user still sees the existing view_count, not the post-increment value). Implementation: do the select first, then the increment at the end. Acceptable inconsistency; no business impact.

Response payloads expose `viewCount` as an integer.

---

## 6. Prompt Composition

`prompt_builder_service.build_prompt(scene_prompt, gender, garments)`:

```python
def build_prompt(
    scene_prompt: str,
    gender: str,                      # "male" | "female"
    garments: list[GarmentForPrompt], # sorted by pipeline before call
) -> str:
    gender_word = "man" if gender.lower() == "male" else "woman"
    phrase = _join_garments(garments)         # see below
    return (
        f"A realistic full-body fashion portrait of a {gender_word}, "
        f"wearing {phrase}, in {scene_prompt.strip()}, smiling, "
        "natural skin texture, detailed fabric, high quality, photographic lighting"
    )
```

`GarmentForPrompt`: `(slot, descriptor)` where `descriptor` is the clothing item's `name` if non-empty, else `category`, else a slot-default (`"a hat" / "a top" / "pants" / "shoes"`).

`_join_garments` ordering: **HAT → TOP → PANTS → SHOES** (user-confirmed). Output form:
- 1 item: `"a red baseball cap"`
- 2 items: `"a red baseball cap and a blue denim jacket"`
- 3 items: `"a red baseball cap, a blue denim jacket, and dark jeans"`
- 4 items: `"a red baseball cap, a blue denim jacket, dark jeans, and white sneakers"`

Article logic (`a` vs `an`): pick by first letter of descriptor. For plural-looking descriptors (ends in `s` like "jeans", "sneakers", "shoes", "pants") drop the article. Simple rule:

```python
def _article(word: str) -> str:
    lower = word.lstrip().lower()
    if lower.endswith(("s",)) and lower.split()[0] not in ("dress", "blouse"):
        return ""
    return "an" if lower[:1] in "aeiou" else "a"
```

(Imperfect — English plural detection is not 100% — but acceptable. The prompt is already templated; small grammar oddities don't meaningfully affect DreamO output quality.)

Negative prompt logic (`get_negative_prompt`) unchanged.

---

## 7. DreamO Service Wire

### 7.1 `DreamO/server.py`

`GenerateRequest` schema:

```python
class GenerateRequest(BaseModel):
    id_image: Optional[str] = None
    garment_images: Optional[list[str]] = None   # NEW: base64 PNGs, 0–4 allowed
    garment_image: Optional[str] = None          # DEPRECATED: single-garment shim
    prompt: str
    # ...unchanged params
```

Handling:
- If `garment_images` is non-empty, use it.
- Else if `garment_image` is set, wrap to `[garment_image]`.
- Else no garment refs.
- At least one of `id_image` or any garment must be present — otherwise HTTP 422.

Build refs:

```python
ref_images, ref_tasks = [], []
if id_image:
    ref_images.append(decode(id_image));    ref_tasks.append("id")
for g in garment_images:
    ref_images.append(decode(g));           ref_tasks.append("ip")
```

The existing `_generator.pre_condition(ref_images, ref_tasks, ref_res, seed)` call is unchanged.

### 7.2 `dreamo_client_service.call_dreamo_generate`

New signature:

```python
async def call_dreamo_generate(
    *,
    id_image_bytes: bytes | None = None,
    garment_images_bytes: list[bytes] | None = None,  # NEW
    prompt: str,
    ...
) -> tuple[bytes, int]:
    payload = { ... }
    if id_image_bytes:
        payload["id_image"] = b64(id_image_bytes)
    if garment_images_bytes:
        payload["garment_images"] = [b64(b) for b in garment_images_bytes]
    ...
```

---

## 8. Pipeline

`run_styled_generation_task`:

1. Load `StyledGeneration` by id; claim (PENDING → PROCESSING), set `started_at=now`, `lease_expires_at=now+15min`, `worker_id=<hostname>`.
2. Query junction: `SELECT ... FROM styled_generation_clothing_items WHERE generation_id=? ORDER BY CASE slot WHEN 'HAT' THEN 1 WHEN 'TOP' THEN 2 WHEN 'PANTS' THEN 3 WHEN 'SHOES' THEN 4 END`.
3. For each junction row: look up the `PROCESSED_FRONT` image for that clothing item. If missing → raise `RuntimeError("Clothing item <id> (slot <X>) has not finished processing")`. Collect bytes into a list, preserve slot order.
4. Download + preprocess selfie (unchanged).
5. `prompt = build_prompt(gen.scene_prompt, gen.gender, [GarmentForPrompt(slot=jr.slot, descriptor=resolve_name(jr.clothing_item)) for jr in junction_rows])`.
6. `await call_dreamo_generate(id_image_bytes=selfie, garment_images_bytes=garments_bytes, prompt=..., ...)`.
7. Ingest result blob, set status=SUCCEEDED.

`_update_progress` also refreshes `lease_expires_at = now + 15min` each call — keeps the lease alive for long-running inferences.

---

## 9. Database Hardening Fixes

### 9.1 Retry blob-ref leak (`styled_generation.py::retry_styled_generation`)

**Current bug:** sets `gen.result_image_blob_hash = None` (and `selfie_processed_blob_hash`) without calling `release()`, leaking refcounts.

**Fix:**

```python
for hash_col in ("result_image_blob_hash", "selfie_processed_blob_hash"):
    h = getattr(gen, hash_col)
    if h:
        blob_service.release(db, h)
        setattr(gen, hash_col, None)
```

### 9.2 `BlobService.release()` missing advisory lock

**Current bug:** `addref` and `ingest_upload` acquire `pg_advisory_xact_lock(hashtext(:h))`; `release` does not. Concurrent `release` + `addref` → lost update.

**Fix:** call `_lock_hash(db, blob_hash)` at the top of `release`.

### 9.3 Stuck `styled_generations` reaper

**Current bug:** if a Celery worker crashes mid-pipeline, the row stays at `PROCESSING` forever.

**Fix:** new Celery beat task `styled_generation.reap_stuck` (hourly):

```python
UPDATE styled_generations
SET status='FAILED',
    failure_reason='Worker timeout (lease expired)',
    updated_at=now()
WHERE status='PROCESSING'
  AND lease_expires_at IS NOT NULL
  AND lease_expires_at < now();
```

Add to `celery_app.conf.beat_schedule` alongside existing `blobs.gc_sweep`.

### 9.4 Orphan physical files

**Current risk:** if `blob_service.ingest_upload` moves a temp file to its content-addressed final location but the enclosing transaction rolls back, the blob table row is gone but the file remains — GC (which scans the table) will never find it.

**Fix:** new Celery beat task `blobs.gc_orphan_files` (weekly, Sunday 03:00 UTC):

```python
def gc_orphan_files():
    storage = get_blob_storage()
    if not isinstance(storage, LocalBlobStorage):
        return  # S3 variant is a separate problem; skip
    db = SessionLocal()
    try:
        known = {h for (h,) in db.execute(select(Blob.blob_hash))}
        for sharded_dir in storage.base.iterdir():
            for sub in sharded_dir.iterdir():
                for file_path in sub.iterdir():
                    h = file_path.name
                    if len(h) == 64 and h not in known and _older_than_24h(file_path):
                        file_path.unlink()
    finally:
        db.close()
```

Older-than-24h guard avoids racing against a transaction that just moved a file but hasn't committed yet. S3 variant is not implemented — documented as a follow-up.

---

## 10. Error Semantics Summary

| Case                                                              | HTTP | Code/Message                                           |
|-------------------------------------------------------------------|------|--------------------------------------------------------|
| `clothing_items` invalid JSON / empty / >4                        | 422  | `clothing_items must be a JSON array of 1 to 4 items`  |
| Duplicate slot in `clothing_items`                                | 422  | `duplicate slot <SLOT>`                                |
| Unknown slot                                                      | 422  | `unknown slot <X>`                                     |
| `gender` invalid                                                  | 422  | `gender must be 'male' or 'female'`                    |
| Any clothing item UUID unknown or not owned by user               | 404  | `Clothing item <id> not found`                         |
| Any referenced garment lacks `PROCESSED_FRONT` at submission time | 409  | `Clothing item <id> (slot <SLOT>) has not finished processing` |
| Same failure detected during pipeline execution                   | –    | Pipeline sets `status=FAILED` with the same string     |

---

## 11. Testing Strategy

Pytest (backend/tests/):

1. **API validation** (`test_styled_generation_api.py`): multi-item happy path, duplicate slot → 422, unknown slot → 422, >4 items → 422, missing gender → 422, single-item legacy shim still works.
2. **Prompt builder** (`test_prompt_builder.py`): 1/2/3/4 garment permutations, male/female wording, missing name → category fallback → slot-default fallback, article `a`/`an`/empty for plural-looking descriptors.
3. **Pipeline** (`test_styled_generation_pipeline.py`): mocked DreamO, asserts ordered garment bytes list passed, asserts specific failure message when a garment has no `PROCESSED_FRONT`.
4. **DreamO server** (`DreamO/tests/test_server.py`): request with `garment_images: [b64,b64]` → builds `ref_tasks=['id','ip','ip']`; backward compat with `garment_image`.
5. **View counts** (`test_view_counts.py`): increment on public GET, no increment by owner, no increment on PRIVATE / DRAFT, popular endpoint ordering correctness.
6. **Blob service** (`test_blob_service.py`): concurrent `release`+`addref` via `pytest-asyncio` and explicit gather; assert refcount never lost (new test).
7. **Retry** (`test_styled_generation_retry.py`): retry releases previous blobs (check `ref_count` decremented).
8. **Reaper** (`test_reap_stuck.py`): row with `lease_expires_at < now` moved to FAILED; row with future lease untouched.

Manual verification for Flutter integration deferred to the frontend owner.

---

## 12. Rollout

Single branch, single PR. Migration is additive + backfill; old workers + new code are briefly incompatible (new pipeline reads junction; old PENDING rows need the backfill step to have run). Deployment order:

1. Apply migration (backfills junction + gender default).
2. Restart backend + celery workers with new code.
3. Rebuild DreamO service image with new `server.py`.

Rollback: migration has a downgrade; revert backend + DreamO images; old code ignores `gender`, `view_count`, and junction rows — the columns/rows just sit unused.

---

## 13. Known Limitations / Follow-ups

- Article grammar in prompt is best-effort, not perfect English.
- Multi-item same slot (e.g. jacket + t-shirt) unsupported by the unique constraint — future work.
- Orphan-file GC for S3 backend not implemented.
- View count increment is not rate-limited; a determined user could inflate their own pack via repeat GETs from another account. Acceptable for now; add per-user-per-hour dedup later if it becomes a problem.
- `source_clothing_item_id` retention carries dead-weight semantics; recommend removing in a future cleanup release once Flutter stops reading it.
