# Multi-Garment DreamO + CreatorItem/ClothingItem Merge + DB Hardening + View Counts — Design

**Date:** 2026-04-20
**Owner:** gch (backend)
**Status:** Draft for review (v2: added CreatorItem↔ClothingItem merge + 3-tier delete lifecycle)

---

## 1. Motivation

Four related backend improvements:

1. **Multi-garment styled generation.** Today `POST /styled-generations` only accepts one clothing item. DreamO's native `pre_condition` already supports a list of reference images with mixed tasks (`id`, `ip`, `style`), but our server wrapper, HTTP client, pipeline, DB model, and prompt builder all hard-code a single garment. We need face + gender + 1–4 garments (one per slot: `HAT`/`TOP`/`PANTS`/`SHOES`) + scene prompt → composed prompt → single generated portrait.
2. **CreatorItem → ClothingItem merge.** `documents/DATA_MODEL.md` specifies a single canonical `ClothingItem` entity; the implementation drifted to two parallel tables (`clothing_items` for consumers, `creator_items` for publishers) with duplicated columns, duplicated pipelines (`clothing_pipeline` vs `creator_pipeline`), and duplicated image/model_3d tables. This refactor consolidates back to one entity so that the "publish my own wardrobe item" flow is a single attribute change instead of re-uploading the same image. It also unblocks requirement 4 (3-tier delete lifecycle on ClothingItem, as user requested).
3. **Database correctness fixes.** Four concrete defects in the existing CAS + styled-generation code (blob leak on retry, missing advisory lock in `release()`, no lease reaper for stuck styled generations, orphan physical files on rollback). Plus 18 additional defects surfaced by the backend audit (see §13).
4. **Platform view counts & popular card packs + 3-tier ClothingItem delete.** Published items and card packs need a view counter so the app can surface the top 10 most-viewed packs on the discovery screen. ClothingItem deletion also needs to respect the publish/download graph: a published item that has downloaders must tombstone instead of hard-deleting, so downloaders keep working.

---

## 2. Scope

In scope:
- **DreamO flow:** `DreamO/server.py`, `backend/app/services/dreamo_client_service.py`, `backend/app/services/prompt_builder_service.py`, `backend/app/services/styled_generation_pipeline.py`, `backend/app/models/styled_generation.py` + new association model, `backend/app/api/v1/styled_generation.py` + schemas.
- **Merge:** `backend/app/models/clothing_item.py` (new columns from CreatorItem), drop `backend/app/models/creator.py` Creator{Item,ItemImage,Model3D,ProcessingTask} classes (keep `CreatorProfile` + `CardPack` + `CardPackItem`); `backend/app/api/v1/creator_items.py` folded into `backend/app/api/v1/clothing.py` (or kept as a thin alias for backward compat, see §4.6); `backend/app/crud/creator_item.py` folded into `backend/app/crud/clothing.py`; `backend/app/services/creator_pipeline.py` folded into `backend/app/services/clothing_pipeline.py`; `backend/app/api/v1/imports.py` rewritten to snapshot from ClothingItem; `backend/app/api/v1/card_packs.py` updated to reference `clothing_items`; schemas updated.
- **DB hardening:** `backend/app/services/blob_service.py` advisory lock in `release()`; `backend/app/tasks.py` reap-stuck + orphan file GC; `backend/app/core/celery_app.py` beat schedule entries; fixes from §14.
- **View counts & delete lifecycle:** `view_count` on `clothing_items` (merged) and `card_packs`; detail-GET increment helpers; `GET /card-packs/popular`; `deleted_at` tombstone column; 3-tier `DELETE /clothing-items/{id}` logic (§4.7); cascade cleanup in consumer un-import.
- **Alembic:** single big migration `20260420_000015_consolidate_and_enhance.py` covering: junction table, gender, lease fields on styled_generations, view_count, deleted_at, merge (data + schema), drop creator_* tables. Non-trivial; see §4.4.

Out of scope:
- Flutter changes (the frontend owner adapts separately; we will keep the old `/creator-items/*` endpoints as thin shims for one release if needed; we will keep the old `clothing_item_id` single-form field accepted for one release, see §5.1).
- Personalized recommendations beyond a raw top-N-by-views list.
- View counts on unpublished `clothing_items`.
- Refactoring `outfit_preview`, `creator_profile`, search/classification services — those keep their current shape.

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

### 4.3 View count — on merged `clothing_items` and `card_packs`

After the merge (§4.6), `clothing_items` carries the publish flag (`catalog_visibility`). View count is added to the merged table:

```sql
ALTER TABLE clothing_items ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_packs     ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0;

CREATE INDEX idx_clothing_items_popular
    ON clothing_items (view_count DESC, created_at DESC)
    WHERE catalog_visibility IN ('PACK_ONLY','PUBLIC')
      AND deleted_at IS NULL;

CREATE INDEX idx_card_packs_popular
    ON card_packs (view_count DESC, created_at DESC)
    WHERE status = 'PUBLISHED';
```

The partial index on `clothing_items` means only "publishable" items participate in popular queries; private wardrobe items are excluded from the ordering, per requirement.

### 4.4 Alembic migration: `20260420_000015_consolidate_and_enhance.py`

Revises: `20260420_000014_link_card_packs_to_public_wardrobes`.

This is one large migration because the merge (§4.6) requires touching many tables at once; splitting it into 3–4 migrations would leave the schema in inconsistent intermediate states that production databases should not pass through.

Upgrade steps, in order (each step wraps in its own transaction via `op.get_bind()`):

**A. Add columns to `clothing_items` that currently live on `creator_items`:**
1. `catalog_visibility VARCHAR(20) NOT NULL DEFAULT 'PRIVATE'` + CHECK constraint `IN ('PRIVATE','PACK_ONLY','PUBLIC')`.
2. `deleted_at TIMESTAMPTZ NULL`.
3. `view_count INTEGER NOT NULL DEFAULT 0`.
4. Rename `imported_from_creator_item_id` → `imported_from_clothing_item_id` (keeps existing data; it currently points into `creator_items.id`, which we will rewrite in step D).

**B. Add columns to `card_packs`:**
5. `view_count INTEGER NOT NULL DEFAULT 0`.

**C. Add columns to `styled_generations`:**
6. `gender VARCHAR(10)` NULLABLE (for backfill first).
7. `started_at`, `lease_expires_at`, `worker_id` (all nullable).

**D. Merge `creator_items` → `clothing_items` (data migration):**
8. For each `creator_items` row `ci`:
   - INSERT into `clothing_items` a new row with `id=ci.id` (reuse UUID so FK from `card_pack_items` doesn't need rewriting), `user_id=ci.creator_id`, `source='OWNED'`, `catalog_visibility=ci.catalog_visibility`, name/description/tags/etc. copied.
   - For each `creator_item_images` row → INSERT into `images` with same `blob_hash`, same `image_type`, same `angle`, `clothing_item_id=ci.id`.
   - For each `creator_models_3d` row → INSERT into `models_3d` with same fields.
9. `card_pack_items`: rename column `creator_item_id` → `clothing_item_id`, retarget FK from `creator_items.id` → `clothing_items.id`. (IDs are preserved so data need not change.)
10. `clothing_items.imported_from_clothing_item_id` already points into the correct ID space (we reused IDs in step 8); FK retargets from `creator_items.id` → `clothing_items.id`.
11. DROP `creator_processing_tasks`, `creator_models_3d`, `creator_item_images`, `creator_items` (in that order to respect FKs).

**E. Styled generation junction + gender backfill:**
12. CREATE `styled_generation_clothing_items` (schema in §4.1).
13. For every `styled_generations` with non-NULL `source_clothing_item_id`, INSERT `(generation_id=sg.id, clothing_item_id=sg.source_clothing_item_id, slot='TOP', position=0)`.
14. `UPDATE styled_generations SET gender='FEMALE' WHERE gender IS NULL` (arbitrary default; legacy prompts didn't use gender), then `ALTER COLUMN gender SET NOT NULL` + `CHECK IN ('MALE','FEMALE')`.

**F. Indexes:**
15. `idx_clothing_items_popular` (partial, see §4.3).
16. `idx_card_packs_popular` (partial).
17. `idx_clothing_items_deleted_at` on `(deleted_at)` `WHERE deleted_at IS NULL` — speeds up the ubiquitous `deleted_at IS NULL` filter added to every query.
18. `idx_clothing_items_catalog_visibility` on `(user_id, catalog_visibility)` for creator-catalog queries.

**G. Concurrency-fix columns from audit (see §14):**
19. CHECK constraint `card_packs.import_count >= 0` (§14 item 7).

Downgrade reverses in strict opposite order. Tombstones (rows with `deleted_at IS NOT NULL`) are restored as active `creator_items` during downgrade — acceptable because downgrade is only used in local dev.

### 4.5 In-flight task compatibility

Before running the pipeline change, existing `PENDING`/`PROCESSING` `styled_generations` rows would have no junction rows — step 13 of the migration backfills one per row, so the new pipeline's query returns exactly one `TOP`-slot entry. Legacy tasks therefore continue to produce a single-garment result using the new code path. Gender defaults to `'FEMALE'` — acceptable because (a) the old prompt template didn't use gender anyway, (b) the user can delete & retry if unhappy.

In-flight `creator_processing_tasks` at migration time will be lost (tables dropped). Because these are asynchronous upload-processing jobs with retry semantics, the practical impact is: a creator with a half-processed upload will see a FAILED status after migration. We accept this because (a) this is dev/single-tenant, and (b) the frontend already has retry logic for FAILED tasks. If the DB has any active creator processing tasks at migration time, the ops runbook says: drain those first (or accept they'll fail).

### 4.6 CreatorItem → ClothingItem merge — semantics

After merge, there is one "piece of clothing" entity: `clothing_items`. A ClothingItem now carries:

- `user_id` — the owner. For items that came from the old `creator_items`, `user_id = creator_id`.
- `source` — `'OWNED'` (user uploaded themselves, or they were a creator who used to upload via `/creator-items`) or `'IMPORTED'` (downloaded from a CardPack).
- `catalog_visibility` — `'PRIVATE'` (never exposed) / `'PACK_ONLY'` (only visible inside CardPacks the user publishes) / `'PUBLIC'` (also listable individually). Default for new uploads stays `'PRIVATE'` to preserve today's "your wardrobe is yours" default; switching to `'PACK_ONLY'` or `'PUBLIC'` is the "publish" action.
- `imported_from_card_pack_id` + `imported_from_clothing_item_id` — provenance for IMPORTED items.
- `deleted_at` — tombstone marker (see §4.7).

**`POST /clothing-items`**: the current upload endpoint stays. It always creates a `source='OWNED'`, `catalog_visibility='PRIVATE'` ClothingItem.

**Publishing**: `PATCH /clothing-items/{id}` already supports editing metadata; we extend its body with a `catalogVisibility` field. Setting it to `'PACK_ONLY'` or `'PUBLIC'` is "publish"; setting back to `'PRIVATE'` is "unpublish" (only allowed if not currently in any PUBLISHED pack — same guard as current creator_items has).

**CardPack composition**: `card_pack_items.clothing_item_id` replaces `creator_item_id`. `POST /card-packs` and `PATCH /card-packs/{id}` bodies take `itemIds: list[UUID]` pointing to ClothingItems the creator owns (`user_id = current_user.id` and `catalog_visibility != 'PRIVATE'`).

**Imports** (`POST /imports/card-pack`): rewritten. For each `CardPackItem` in the pack, snapshot the referenced `ClothingItem` into a new row with `source='IMPORTED'`, blobs shared via refcount (unchanged mechanism). `imported_from_clothing_item_id` points to the canonical (publisher's) row.

**Old `/creator-items/*` endpoints**: keep as thin shims (one-release deprecation) that translate:
- `POST /creator-items` → delegates to clothing upload with `catalog_visibility='PACK_ONLY'` default.
- `GET /creator-items/{id}` → 302 redirect to `GET /clothing-items/{id}` (or return the same body inline, simpler).
- `PATCH /creator-items/{id}` → `PATCH /clothing-items/{id}`.
- `DELETE /creator-items/{id}` → `DELETE /clothing-items/{id}` (picks up new 3-tier logic).

**Old pipeline**: `creator_pipeline.py` merged into `clothing_pipeline.py`. The processing stages are already nearly identical; the minor differences (where creator pipeline skipped some consumer-specific hooks) are reconciled by adding conditional branches based on `source`/`catalog_visibility`.

**Queries to update**: every `SELECT ... FROM clothing_items` gains `AND deleted_at IS NULL`. We do this via a SQLAlchemy `@declared_attr` base-class filter OR by updating each CRUD call site. Recommended: explicit filter at each call site (easier to audit and to selectively break when we need to see tombstones, e.g. admin / cleanup tools). Count of touch points is ~12 (all in `backend/app/crud/clothing.py`, `creator_item.py` soon-to-be-folded, and direct queries in API handlers).

### 4.7 ClothingItem 3-tier delete lifecycle

`DELETE /clothing-items/{id}` becomes:

```
# Transaction: SELECT FOR UPDATE on the item, then:
import_count = count(clothing_items WHERE imported_from_clothing_item_id = self.id)
in_published_pack = EXISTS(
    card_pack_items JOIN card_packs
    WHERE card_pack_items.clothing_item_id = self.id
      AND card_packs.status = 'PUBLISHED'
)

if not in_published_pack:
    # Case 1: never published (or only in DRAFT/ARCHIVED packs)
    HARD_DELETE()
elif import_count == 0:
    # Case 2: published but no one downloaded
    HARD_DELETE()
else:
    # Case 3: published and has downloads
    TOMBSTONE()
```

Where:

- **HARD_DELETE:**
  1. Collect all `images.blob_hash` + `models_3d.blob_hash` for this item.
  2. Delete `wardrobe_items` rows linking it.
  3. Delete `card_pack_items` rows referencing it (from any DRAFT/ARCHIVED packs — none PUBLISHED by precondition).
  4. `db.delete(item)` — cascades drop `images`, `models_3d`, `processing_tasks` via `cascade="all, delete-orphan"`.
  5. Release each blob (now with lock per §14 item 1).
- **TOMBSTONE:**
  1. `item.deleted_at = now()`.
  2. Delete `wardrobe_items` rows linking it (creator no longer "owns" it in any wardrobe view).
  3. Delete `card_pack_items` rows referencing it (remove from all packs — future importers won't see it). Note: existing PUBLISHED packs become shorter; if a pack ends up empty that's the creator's problem.
  4. Delete `images` and `models_3d` belonging to this item; release their blobs. Consumer-side IMPORTED ClothingItems have *their own* `images` rows holding independent blob refs, so blobs don't get physically deleted as long as ≥1 importer still holds them.
  5. Keep the ClothingItem row itself (with `deleted_at` set, `images=[]`, `models_3d=None`). It serves only as an anchor for `imported_from_clothing_item_id` backlinks.

**Query behavior on tombstones:** all `GET` and `PATCH` paths for ClothingItem filter `deleted_at IS NULL`; tombstones are invisible to the creator, cannot be published or edited. Only the implicit `imported_from_clothing_item_id` JOIN (when rendering an IMPORTED ClothingItem's detail with provenance info) can touch a tombstone — and we display it as "creator removed this item" rather than returning its fields.

**Tombstone cleanup** (deferred GC): when consumer runs `DELETE /clothing-items/{id}` on an IMPORTED item, or `DELETE /imports/card-pack/{pack_id}`, we additionally check: for each `imported_from_clothing_item_id` that was released, if the target row has `deleted_at IS NOT NULL` AND there are no other ClothingItems pointing to it → hard-delete it now. This keeps tombstones from accumulating forever.

**Concurrency:** the whole 3-tier logic runs inside a transaction that holds `SELECT ... FOR UPDATE` on the ClothingItem. The `import_count` query and `in_published_pack` EXISTS must also be inside that transaction. Concurrent importer: would need to SELECT the pack, then INSERT `clothing_items` IMPORTED row. The importer should also take a pack-level advisory lock to serialize with delete — see §14 for the matching fix.

**Creator account deletion** (`users.id` CASCADE'd): a cascade delete of the creator's ClothingItem rows would break IMPORTED items' backlinks (set to NULL via `ondelete=SET NULL` in §4.6's schema). Consumer wardrobe still works, just loses provenance. Acceptable; matches current behavior for creator_items.

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
| `GET /api/v1/clothing-items/{item_id}`      | `clothing_items`| `catalog_visibility != 'PRIVATE'` AND `deleted_at IS NULL` AND (not authenticated OR `viewer_user_id != user_id`) |
| `GET /api/v1/card-packs/{pack_id}`          | `card_packs`    | `status = 'PUBLISHED'` AND (not authenticated OR `viewer_user_id != creator_id`) |
| `GET /api/v1/card-packs/share/{share_id}`   | `card_packs`    | `status = 'PUBLISHED'` AND (not authenticated OR `viewer_user_id != creator_id`) |

(The legacy `GET /api/v1/creator-items/{item_id}` shim endpoint forwards to the clothing-items one and inherits its increment behavior.)

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

## 9. Database Hardening Fixes (Core Four)

See §13 for the additional defects found during the audit pass; they are equally in-scope for this change.

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

## 13. Additional Defects Surfaced by Audit

Audit pass over `backend/app/` turned up 18 new issues (beyond the 4 already called out in §9). All are folded into this spec's implementation scope. Ranked by severity:

### High

1. **`card_packs.import_count` unprotected RMW** — `backend/app/api/v1/imports.py:124` and `:157` read-then-write `pack.import_count` without `SELECT ... FOR UPDATE`. Concurrent imports/unimports can double-count or miss decrements. **Fix**: fetch `pack` with `.with_for_update()` in both handlers before touching the counter. Also add CHECK `import_count >= 0` (migration step 19).
2. **`DELETE /card-packs/{pack_id}` TOCTOU on import count** — `backend/app/api/v1/card_packs.py:191` counts imports before issuing the delete, but the row isn't locked for the duration. A concurrent `POST /imports/card-pack` between the count and the delete bypasses the guard. **Fix**: take `FOR UPDATE` on the pack row and re-verify count under the lock; import endpoint also takes `FOR UPDATE` on the target pack before inserting the `CardPackImport` row.
3. **`ProcessingTask.attempt_no` / retry race** — `backend/app/api/v1/clothing.py` retry path reads `attempt_no`, increments, then writes without FOR UPDATE; two concurrent retries on the same failed task can collide. **Fix**: lock the task row (or re-use `uq_processing_tasks_active_item` to reject the 2nd retry with 409). Also gate retry with `status != 'PENDING'` check inside the lock.
4. **`SECRET_KEY` default ships as literal**: `backend/app/core/config.py:49` sets `SECRET_KEY: str = "CHANGE-ME-in-production"`. A misconfigured deploy leaves this value in use and all JWTs forgeable. **Fix**: raise at `Settings.__init__` if the value equals the default string; add a clear startup log otherwise.

### Medium

5. **`import_count` rollback leak in import loop** — `backend/app/api/v1/imports.py:104` loops `blob_service.addref()` per image. If the 5th addref fails, the prior 4 are still in the transaction; commit fails → rollback → both the CardPackImport row AND the 4 addref increments roll back. Actually the current code is *correct* on rollback, but there's a subtle bug: `addref` requires the blob to exist; if a creator hard-deleted their side's images during an in-flight import, `addref` throws `BlobNotFoundError` and the whole import dies. **Fix**: upgrade the error to a user-friendly 409 "Pack contents changed during import, try again", not a 500.
6. **`_update_progress` commits per microstep** — `backend/app/services/clothing_pipeline.py` and `styled_generation_pipeline.py` commit on every progress tick. This is fine for visibility but (a) multiplies transaction overhead, (b) each commit releases row locks we may want to hold. **Fix**: batch progress updates to at most N per second, OR keep per-tick commits but explicitly re-fetch with FOR UPDATE where locking matters. Accept the small perf cost for progress visibility; don't actually batch — just document the trade-off and ensure no logic depends on cross-tick locking.
7. **`outfit_preview` / `creator_pipeline` task-dispatch-failure orphan** — when `celery.apply_async` fails after the DB row is committed, the row is stuck at `PENDING` forever. Same pattern as `styled_generations` but on additional services. **Fix**: the stuck-task reaper task (§9.3) is extended to also cover `outfit_preview_tasks` and (post-merge) `processing_tasks`. Creator pipeline goes away with the merge.
8. **N+1 in `GET /wardrobes`** — `backend/app/api/v1/wardrobe.py:108-112` calls `crud_wardrobe.get_item_count(w.id)` once per wardrobe. On a user with 50 wardrobes, 51 queries. **Fix**: replace with one `SELECT wardrobe_id, COUNT(*) FROM wardrobe_items WHERE wardrobe_id IN (...) GROUP BY wardrobe_id`, zip results.
9. **N+1 in `GET /wardrobes/public`** — same pattern at `backend/app/api/v1/wardrobe.py:128-131`.
10. **`GET /files/card-packs/{id}/cover` potentially unauthenticated** — if a creator has a DRAFT pack with a cover already uploaded, the cover blob is servable by any unauthenticated user that knows the pack ID. **Fix**: in `backend/app/api/v1/files.py`, require the pack is `status='PUBLISHED'` OR the authenticated user is the creator.
11. **`get_optional_current_user_id` used for logic branching** — `backend/app/api/v1/card_packs.py:82-95` returns different data depending on whether an anonymous visitor or the creator is reading. If the JWT-validation path has any bug that silently returns `None` instead of a specific user, the creator could read others' DRAFT packs. **Fix**: already partially defended (falls back to `get_public_card_pack`), but add an explicit test for this scenario.
12. **`processing_task_service.claim_task` race** — same "read-then-update" pattern as retry; two workers can both claim a PENDING task. **Fix**: use `UPDATE ... SET status='PROCESSING' WHERE id=? AND status='PENDING' RETURNING id` (atomic compare-and-swap) instead of read-modify-write.

### Low

13. **Missing boundary size check on clothing-item upload** — `backend/app/api/v1/clothing.py` relies on `ingest_upload`'s internal `max_size`, not an explicit API-boundary 413. Harmless today but inconsistent with `styled_generation.py:114`. **Fix**: add `if len(front_bytes) > settings.MAX_UPLOAD_SIZE_BYTES: raise 413` at API layer.
14. **`backend/app/api/deps.py` uses `db.get(User, user_id)`** — pulls from identity map if present, missing a freshly-deactivated user. **Fix**: use `.filter().first()` or explicit `db.expire(user)` before check.
15. **`outfit_preview_service` release swallow** — in the exception handler, failed `blob_service.release` is caught and passed. **Fix**: upgrade to `logger.error` and emit a metric so orphan blobs get noticed.
16. **Generic 500 where 404/409 is clearer** — `DELETE /clothing-items/{id}` raises generic errors for "item locked by processing task" vs "not found". **Fix**: distinct status codes.
17. **ALGORITHM hardcoded HS256** — `config.py:50`. Acceptable for now (single-tenant), add to follow-ups list.
18. **`outfit_preview` list N+1** (suspected, not confirmed by reading code) — ensure `selectinload(OutfitPreviewTask.items)` on list queries. Quick verification during implementation.

---

## 14. Known Limitations / Follow-ups

- Article grammar in prompt is best-effort, not perfect English.
- Multi-item same slot (e.g. jacket + t-shirt) unsupported by the unique constraint — future work.
- Orphan-file GC for S3 backend not implemented.
- View count increment is not rate-limited; a determined user could inflate their own pack via repeat GETs from another account. Acceptable for now; add per-user-per-hour dedup later if it becomes a problem.
- `source_clothing_item_id` retention carries dead-weight semantics; recommend removing in a future cleanup release once Flutter stops reading it.
