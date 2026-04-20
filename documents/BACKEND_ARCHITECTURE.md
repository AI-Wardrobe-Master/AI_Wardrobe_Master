# AI Wardrobe Master - Backend Architecture (FastAPI)

## Overview
This document defines the backend architecture using FastAPI, PostgreSQL, and S3/MinIO for the AI Wardrobe Master application.

---

## Technology Stack

### Core Technologies
- **API Framework**: FastAPI 0.109+
- **Database**: PostgreSQL 15+
- **Object Storage**: S3 / MinIO / Local File System
- **ORM**: SQLAlchemy 2.0+
- **Migration**: Alembic
- **Authentication**: JWT (python-jose)
- **Validation**: Pydantic V2
- **Image Processing**: Pillow, OpenCV
- **AI/ML**: TensorFlow Lite / PyTorch (optional)

### Development Tools
- **API Documentation**: Swagger UI (built-in FastAPI)
- **Testing**: pytest, pytest-asyncio
- **Code Quality**: black, flake8, mypy
- **Container**: Docker, Docker Compose

---

## Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py                      # FastAPI application entry
│   ├── config.py                    # Configuration management
│   │
│   ├── api/                         # API endpoints
│   │   ├── __init__.py
│   │   ├── deps.py                  # Dependencies (DB session, auth)
│   │   └── v1/
│   │       ├── __init__.py
│   │       ├── router.py            # Main router
│   │       ├── auth.py              # Authentication endpoints
│   │       ├── clothing.py          # Clothing item endpoints
│   │       ├── wardrobe.py          # Wardrobe endpoints
│   │       ├── me.py                # Unified user context endpoint
│   │       ├── creators.py          # Creator profile endpoints
│   │       ├── creator_items.py     # Creator catalog item endpoints
│   │       ├── card_packs.py        # Card pack endpoints
│   │       ├── imports.py           # Import operations
│   │       ├── outfits.py           # Saved outfit endpoints
│   │       ├── outfit_preview.py    # Outfit preview task endpoints
│   │       └── image.py             # Image processing endpoints
│   │
│   ├── models/                      # SQLAlchemy models
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── clothing_item.py
│   │   ├── wardrobe.py
│   │   ├── creator.py
│   │   ├── outfit.py
│   │   ├── card_pack.py
│   │   ├── import_history.py
│   │   ├── outfit_preview_task.py
│   │   └── associations.py          # Many-to-many tables
│   │
│   ├── schemas/                     # Pydantic schemas
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── clothing_item.py
│   │   ├── wardrobe.py
│   │   ├── me.py
│   │   ├── creator.py
│   │   ├── outfit.py
│   │   ├── card_pack.py
│   │   ├── import_history.py
│   │   └── outfit_preview.py
│   │
│   ├── crud/                        # CRUD operations
│   │   ├── __init__.py
│   │   ├── base.py                  # Base CRUD class
│   │   ├── clothing.py
│   │   ├── wardrobe.py
│   │   ├── creator.py
│   │   ├── card_pack.py
│   │   ├── import_history.py
│   │   ├── outfit.py
│   │   └── outfit_preview.py
│   │
│   ├── services/                    # Business logic services
│   │   ├── __init__.py
│   │   ├── auth_service.py          # Authentication logic
│   │   ├── storage_service.py       # S3/MinIO/Local storage
│   │   ├── image_service.py         # Image processing
│   │   ├── ai_service.py            # AI classification
│   │   ├── search_service.py        # Search functionality
│   │   ├── upload_validation_service.py
│   │   ├── virtual_wardrobe_service.py
│   │   ├── card_pack_import_service.py
│   │   ├── outfit_service.py
│   │   └── outfit_preview_service.py
│   │
│   ├── core/                        # Core utilities
│   │   ├── __init__.py
│   │   ├── security.py              # Password hashing, JWT
│   │   ├── config.py                # Settings
│   │   └── exceptions.py            # Custom exceptions
│   │
│   └── db/                          # Database
│       ├── __init__.py
│       ├── base.py                  # Base model
│       ├── session.py               # Database session
│       └── init_db.py               # Database initialization
│
├── alembic/                         # Database migrations
│   ├── versions/
│   └── env.py
│
├── tests/                           # Tests
│   ├── api/
│   ├── crud/
│   └── services/
│
├── scripts/                         # Utility scripts
│   ├── init_db.py
│   └── seed_data.py
│
├── requirements.txt                 # Python dependencies
├── Dockerfile
├── docker-compose.yml
├── alembic.ini
├── .env.example
└── README.md
```

---

## Missing Feature Alignment

The archived `backend_missing_feature_design` set has been absorbed into this document. When any older examples below conflict with this section, **this section is authoritative**.

### Route and Module Boundaries

- `me.py` returns unified user context plus creator capability flags for Flutter shell gating.
- `creator_items.py` is a legacy façade. The old `creator_items` table has been merged into `clothing_items`; this router remains solely as a backwards-compatible shim delegating to the unified clothing endpoints.
- `clothing.py` is now the single source of truth for both consumer and creator items. Publishing, visibility, and import are all expressed on the `clothing_items` row via `catalog_visibility`.
- `creators.py` handles public creator browse plus authenticated self-service profile and dashboard access.
- `card_packs.py` owns draft/publish/archive/delete transitions and public share reads, and exposes the new `/card-packs/popular` ranking endpoint.
- `imports.py` is a transactional route surface and must delegate write orchestration to a service.
- `outfit_preview.py` is isolated from clothing processing and owns preview task creation, polling, and save-to-outfit.
- `outfits.py` only manages saved outfit metadata and retrieval. It does not behave like a generation task controller.

### Data Model Overrides

- Imported-item provenance is stored on `clothing_items` via origin fields, not in a standalone `provenance` table.
- **Creator/consumer clothing table merge.** There is exactly one canonical table — `clothing_items`. The previous `creator_items` table has been folded in. Every item (owned, imported, or creator-authored) carries `catalog_visibility` ∈ {`PRIVATE`, `PACK_ONLY`, `PUBLIC`}, which drives public discovery filters. `card_pack_items.clothing_item_id` references this merged table directly; there is no separate `creator_item_id`. Data migration `20260420_000015` performs the move.
- There is a single async pipeline queue, `clothing_pipeline`, used for both consumer uploads and creator-authored items. The old `creator_pipeline` name is no longer used.
- `wardrobes` must support `is_system_managed` and `system_key`, with `DEFAULT_VIRTUAL_IMPORTED` reserved for the auto-created imported-content wardrobe.
- Creator business data should live in `creator_profiles` keyed by `user_id`, with explicit `PENDING / ACTIVE / SUSPENDED` lifecycle state.
- Import flow requires `import_histories` plus `import_history_items` so that cloned imported items can be traced back to both pack and source item. The self-reference field on imported copies is now `imported_from_clothing_item_id` (was `imported_from_creator_item_id`).
- Outfit preview is a separate domain modeled by `outfit_preview_tasks` and `outfit_preview_task_items`.
- `outfits` represent confirmed saved results and may reference `preview_task_id`; they should not also serve as asynchronous processing records.
- **Styled generation multi-garment model.** `styled_generations` now carries a `gender VARCHAR(10)` column, and the many-to-many `styled_generation_clothing_items` junction table (`styled_generation_id`, `clothing_item_id`, `slot ∈ {HAT,TOP,PANTS,SHOES}`, `sort_order`) replaces the single `source_clothing_item_id` FK for inference. The FK is retained on `styled_generations` for backward-compat reads.

### Service Boundaries

- `upload_validation_service.py` performs MIME, extension, decodability, and dimension checks before accepting uploads.
- `virtual_wardrobe_service.py` exposes `get_or_create_virtual_wardrobe(user_id)` and is used both by API convenience endpoints and import orchestration.
- `card_pack_import_service.py` owns clone creation, provenance population, virtual wardrobe insertion, and import history writes in a single transaction.
- `outfit_service.py` manages saved outfit reads and metadata updates.
- `outfit_preview_service.py` owns prompt selection, provider invocation, result persistence, and task state updates.

### Ownership And Transaction Rules

- Public visibility filters such as `PUBLISHED` and `catalog_visibility != PRIVATE` must be enforced in the query layer, not trimmed after object loading.
- Write paths must query by both resource id and owner id, for example `get_owned_card_pack`, `get_owned_creator_item`, and `get_owned_outfit`.
- CRUD helpers may continue to serve simple reads, but transactional writes for imports, publish/archive transitions, and preview save flows must commit at the service layer.
- State-changing endpoints should prefer row-level locking or equivalent transactional guards and return `409` for domain conflicts.

### User Id And Ownership Dependencies

- `get_current_creator_user_id` should build on `get_current_user_id` and then verify that a creator profile exists and is `ACTIVE`.
- Creator-only routes must depend on `get_current_creator_user_id`, not on a loose `user_type == CREATOR` check.
- Ownership-safe helpers should exist for every mutating resource boundary:
  - `get_owned_creator_profile(db, *, creator_id, current_user_id)`
  - `get_owned_creator_item(db, *, item_id, creator_id)`
  - `get_owned_card_pack(db, *, pack_id, creator_id)`
  - `get_owned_outfit(db, *, outfit_id, user_id)`
- These helpers should return `None` when ownership fails so routes can map the result to `404` without leaking resource existence.
- Transactional flows must load resources through ownership-safe helpers before any state transition, then commit in the service layer after all validations pass.

### Async Execution Split

- `processing_tasks` remains the async pipeline for clothing asset preparation.
- `outfit_preview_tasks` is a distinct queue / worker domain for generated try-on previews.
- Provider-specific prompt selection and image ordering belong in backend services; frontend submits structured metadata and referenced clothing item ids only.

## Database Schema (PostgreSQL)


### PostgreSQL Tables

```sql
-- users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('CONSUMER', 'CREATOR')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- user_profiles table
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    display_name VARCHAR(100),
    avatar_url TEXT,
    bio TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- clothing_items table
CREATE TABLE clothing_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source VARCHAR(20) NOT NULL CHECK (source IN ('OWNED', 'IMPORTED')),
    
    -- Tag-based classification (JSONB for flexible querying)
    predicted_tags JSONB NOT NULL DEFAULT '[]',  -- Immutable AI predictions
    final_tags JSONB NOT NULL DEFAULT '[]',      -- User-confirmed tags (used for search)
    is_confirmed BOOLEAN DEFAULT FALSE,
    
    -- Metadata
    name VARCHAR(200),
    description TEXT,
    custom_tags TEXT[],  -- User-defined freeform tags
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_clothing_user ON clothing_items(user_id);
CREATE INDEX idx_clothing_source ON clothing_items(source);
CREATE INDEX idx_clothing_final_tags ON clothing_items USING GIN(final_tags);  -- GIN index for JSONB search
CREATE INDEX idx_clothing_custom_tags ON clothing_items USING GIN(custom_tags);

-- Example tag structure in JSONB:
-- predicted_tags: [
--   {"key": "category", "value": "T_SHIRT"},
--   {"key": "color", "value": "blue"},
--   {"key": "pattern", "value": "striped"}
-- ]

-- images table (stores S3/MinIO paths)
CREATE TABLE images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    image_type VARCHAR(20) NOT NULL CHECK (image_type IN (
        'ORIGINAL_FRONT', 'ORIGINAL_BACK',
        'PROCESSED_FRONT', 'PROCESSED_BACK',
        'ANGLE_VIEW'
    )),
    storage_path TEXT NOT NULL,  -- S3/MinIO path or local file path
    angle INTEGER CHECK (angle IN (0, 45, 90, 135, 180, 225, 270, 315)),
    file_size BIGINT,
    mime_type VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_images_clothing ON images(clothing_item_id);

-- provenance is no longer modeled as a standalone table.
-- Imported-item origin fields now live on clothing_items and import history tables.

-- wardrobes table
CREATE TABLE wardrobes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    wardrobe_type VARCHAR(20) NOT NULL CHECK (wardrobe_type IN ('REGULAR', 'VIRTUAL')),
    description TEXT,
    item_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_wardrobe_user ON wardrobes(user_id);
CREATE INDEX idx_wardrobe_type ON wardrobes(wardrobe_type);

-- wardrobe_items junction table
CREATE TABLE wardrobe_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wardrobe_id UUID NOT NULL REFERENCES wardrobes(id) ON DELETE CASCADE,
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    display_order INTEGER,
    UNIQUE(wardrobe_id, clothing_item_id)
);

CREATE INDEX idx_wardrobe_items_wardrobe ON wardrobe_items(wardrobe_id);
CREATE INDEX idx_wardrobe_items_clothing ON wardrobe_items(clothing_item_id);

-- outfits table
CREATE TABLE outfits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    thumbnail_path TEXT,  -- S3/MinIO path
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_outfit_user ON outfits(user_id);

-- outfit_items table
CREATE TABLE outfit_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    outfit_id UUID NOT NULL REFERENCES outfits(id) ON DELETE CASCADE,
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id),
    layer INTEGER NOT NULL,
    position_x DECIMAL(5,4) NOT NULL CHECK (position_x BETWEEN 0 AND 1),
    position_y DECIMAL(5,4) NOT NULL CHECK (position_y BETWEEN 0 AND 1),
    scale DECIMAL(3,2) NOT NULL CHECK (scale BETWEEN 0.5 AND 2.0),
    rotation INTEGER NOT NULL CHECK (rotation BETWEEN 0 AND 359)
);

CREATE INDEX idx_outfit_items_outfit ON outfit_items(outfit_id);

-- creators table (extends users)
CREATE TABLE creators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACTIVE', 'SUSPENDED')),
    display_name VARCHAR(100),
    brand_name VARCHAR(200),
    bio TEXT,
    avatar_url TEXT,
    website_url TEXT,
    social_links JSONB,  -- {platform: url}
    follower_count INTEGER DEFAULT 0,
    pack_count INTEGER DEFAULT 0,
    is_verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_creator_status ON creators(status);
CREATE INDEX idx_creator_verified ON creators(is_verified);

-- card_packs table
CREATE TABLE card_packs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES creators(user_id) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    cover_image_path TEXT,  -- S3/MinIO path
    pack_type VARCHAR(30) NOT NULL CHECK (pack_type IN ('CLOTHING_COLLECTION', 'OUTFIT')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
    share_link VARCHAR(100) UNIQUE,
    import_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_card_pack_creator ON card_packs(creator_id);
CREATE INDEX idx_card_pack_status ON card_packs(status);
CREATE INDEX idx_card_pack_share_link ON card_packs(share_link);

-- card_pack_items junction table
CREATE TABLE card_pack_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_pack_id UUID NOT NULL REFERENCES card_packs(id) ON DELETE CASCADE,
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    display_order INTEGER,
    UNIQUE(card_pack_id, clothing_item_id)
);

CREATE INDEX idx_card_pack_items_pack ON card_pack_items(card_pack_id);

-- import_history table
CREATE TABLE import_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_pack_id UUID NOT NULL REFERENCES card_packs(id),
    creator_id UUID NOT NULL REFERENCES users(id),
    item_count INTEGER NOT NULL,
    imported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_import_user ON import_history(user_id);
CREATE INDEX idx_import_pack ON import_history(card_pack_id);

-- models_3d table (stores 3D model references, generated by Hunyuan3D-2)
CREATE TABLE models_3d (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clothing_item_id UUID UNIQUE NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    model_format VARCHAR(10) NOT NULL DEFAULT 'glb',
    storage_path TEXT NOT NULL,
    vertex_count INTEGER,
    face_count INTEGER,
    file_size BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_models_3d_clothing ON models_3d(clothing_item_id);

-- processing_tasks table (tracks async processing: bg removal, 3D gen, angle rendering)
CREATE TABLE processing_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    task_type VARCHAR(30) NOT NULL CHECK (
        task_type IN ('BACKGROUND_REMOVAL', '3D_GENERATION', 'ANGLE_RENDERING', 'FULL_PIPELINE')
    ),
    attempt_no INTEGER NOT NULL DEFAULT 1 CHECK (attempt_no >= 1),
    retry_of_task_id UUID REFERENCES processing_tasks(id) ON DELETE SET NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (
        status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED')
    ),
    progress INTEGER DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
    error_message TEXT,
    worker_id VARCHAR(255),
    lease_expires_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_processing_tasks_clothing ON processing_tasks(clothing_item_id);
CREATE INDEX idx_processing_tasks_status ON processing_tasks(status);
CREATE UNIQUE INDEX uq_processing_tasks_active_item
    ON processing_tasks(clothing_item_id)
    WHERE status IN ('PENDING', 'PROCESSING');

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_clothing_items_updated_at BEFORE UPDATE ON clothing_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_wardrobes_updated_at BEFORE UPDATE ON wardrobes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_outfits_updated_at BEFORE UPDATE ON outfits
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

---

## Processing Pipeline Execution

### Clothing Digitization Pipeline (Hunyuan3D)

- API writes are short-lived: store original uploads, create `clothing_items`, create `processing_tasks(PENDING)`, then enqueue Celery.
- Celery workers claim a task atomically before moving it to `PROCESSING`.
- Worker failures mark the task `FAILED`, keep original uploads, and remove all derived database records and files.
- Retry creates a new task row instead of mutating the failed task, preserving audit history.
- Queue: `clothing_pipeline`

### Styled Generation Pipeline (DreamO)

A separate async pipeline for personalized fashion photo generation:

- **Endpoint**: `POST /api/v1/styled-generations` creates a `StyledGeneration` record, inserts one `styled_generation_clothing_items` row per submitted garment (1–4, unique slots), and enqueues to the `styled_generation` Celery queue.
- **Queue**: `styled_generation` (separate from `clothing_pipeline`)
- **Worker**: `celery-styled-gen` Docker service
- **Pipeline steps**:
  1. Load the gender and all slot→garment rows from `styled_generation_clothing_items` via the junction table (ordered HAT → TOP → PANTS → SHOES).
  2. Validate every garment has a PROCESSED_FRONT image (from Hunyuan3D pipeline).
  3. Download and preprocess selfie (face detection, background removal, white bg composite).
  4. Build composite prompt from gender-aware templates + slot-ordered garment descriptions + user scene description.
  5. Call isolated DreamO HTTP service (port 9000) for inference, passing `garment_images: [...]` (list).
  6. Store result image and update status to SUCCEEDED.
- **DreamO** runs as a separate Docker service with its own Python environment (torch, diffusers, transformers pinned to specific versions).
- Retry resets the record to PENDING and re-dispatches, but before re-enqueueing it releases any blobs produced by the prior failed attempt (result image, intermediate selfie variants).

### StyledGeneration Entity

```sql
CREATE TABLE styled_generations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_clothing_item_id UUID REFERENCES clothing_items(id) ON DELETE SET NULL,
    -- kept as a backwards-compat "first garment" shortcut; real garments live in
    -- the junction table styled_generation_clothing_items
    gender VARCHAR(10) NOT NULL CHECK (gender IN ('male','female')),
    selfie_original_path TEXT NOT NULL,
    selfie_processed_path TEXT,
    scene_prompt TEXT NOT NULL,
    negative_prompt TEXT,
    dreamo_version VARCHAR(10) NOT NULL DEFAULT 'v1.1',
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING','PROCESSING','SUCCEEDED','FAILED')),
    progress INTEGER NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
    result_image_path TEXT,
    failure_reason TEXT,
    guidance_scale FLOAT NOT NULL DEFAULT 4.5,
    seed INTEGER NOT NULL DEFAULT -1,
    width INTEGER NOT NULL DEFAULT 1024,
    height INTEGER NOT NULL DEFAULT 1024,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Multi-garment junction. 1-4 rows per generation, unique slots per generation.
CREATE TABLE styled_generation_clothing_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    styled_generation_id UUID NOT NULL REFERENCES styled_generations(id) ON DELETE CASCADE,
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id),
    slot VARCHAR(10) NOT NULL CHECK (slot IN ('HAT','TOP','PANTS','SHOES')),
    sort_order INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(styled_generation_id, slot)
);
CREATE INDEX idx_sgci_generation ON styled_generation_clothing_items(styled_generation_id);
CREATE INDEX idx_sgci_clothing ON styled_generation_clothing_items(clothing_item_id);
```

### Content-Addressed Storage (CAS)

All binary assets (images, GLB models) are stored using content-addressed storage. Files are identified by their SHA-256 hash, not by user/item paths.

**Architecture:**
- `blobs` table: central registry with `blob_hash CHAR(64)` PK, `byte_size`, `mime_type`, `ref_count`, `pending_delete_at`
- `BlobStorage` (byte layer): `LocalBlobStorage` or `S3BlobStorage`, stores files at `blobs/{hash[:2]}/{hash[2:4]}/{hash}`
- `BlobService` (DB layer): manages ref_count via `ingest_upload()`, `addref()`, `release()`
- Concurrency safety: PostgreSQL advisory locks (`pg_advisory_xact_lock`) serialize per-hash operations
- GC: Celery Beat sweeps blobs with `ref_count=0` after 24h grace period

**Business tables reference blobs via `blob_hash CHAR(64) FK`:**
- `images.blob_hash`, `models_3d.blob_hash` (consumer clothing)
- `creator_item_images.blob_hash`, `creator_models_3d.blob_hash` (creator clothing)
- `styled_generations.selfie_original_blob_hash`, `.selfie_processed_blob_hash`, `.result_image_blob_hash`
- `outfit_preview_tasks.person_image_blob_hash`, `.preview_image_blob_hash`
- `outfit_preview_task_items.garment_image_blob_hash`
- `outfits.preview_image_blob_hash`
- `card_packs.cover_image_blob_hash`

**URL delivery:** All file URLs use business paths (`/files/clothing-items/{id}/{kind}`), never expose hashes. The `/files` router resolves `blob_hash` internally and streams bytes.

### Card Pack Import Flow

When a consumer imports a published card pack:
1. `card_pack_imports` record created (tracks import binding)
2. For each `creator_item` in the pack: a snapshot `clothing_items` row is created with `source='IMPORTED'`, copying metadata (tags, name, description) but sharing blob references via `addref()`
3. `import_count` on the card pack is incremented
4. Consumer can delete individual imported items or un-import the entire pack

**Deletion rules (3-tier clothing item lifecycle, spec §4.7):**

`DELETE /clothing-items/{id}` dispatches as follows:

1. **Hard delete — private or never published.** If `catalog_visibility = PRIVATE`, or the item has never been referenced by a `PUBLISHED` card pack, the row is removed and `BlobService.release()` runs for every asset.
2. **Hard delete — published but zero downstream downloaders.** If the item has been published (`PACK_ONLY` / `PUBLIC`) but no consumer import row currently references it, the row is still removed. Same release path.
3. **Tombstone — published with live downstream imports.** If at least one `clothing_items` row has `imported_from_clothing_item_id = <id>`, the row is retained but `deleted_at` is set. It is filtered out of every list / discovery endpoint. Blob references remain until the consumer un-imports; consumer un-import cascades the tombstone (its downstream copies are deleted, which triggers blob `release()`).

**Other deletion constraints:**
- Consumer clothing_item (OWNED or IMPORTED): always deletable (releases blob refs).
- Card pack ARCHIVE: always allowed (hides from discovery, doesn't affect imports).
- Card pack HARD DELETE: blocked while `card_pack_imports` count > 0.

### View Counts and Popular Packs

`clothing_items` and `card_packs` both carry a `view_count INTEGER NOT NULL DEFAULT 0` column, incremented atomically on every detail GET (`UPDATE ... SET view_count = view_count + 1 RETURNING view_count`). The same transaction also performs the read, so the response reflects the post-increment value.

Rules:
- Only `PUBLISHED` packs accrue views (the counter is still persisted for drafts, but all paths that read it skip non-published rows).
- Self-views are skipped: if the authenticated caller owns the pack (or the creator-authored item), the increment is short-circuited.
- `GET /api/v1/card-packs/popular?limit=10` returns `PUBLISHED` packs ordered by `view_count DESC, published_at DESC`.

### Database Hardening

- `release()` acquires the per-hash `pg_advisory_xact_lock` before decrementing `ref_count`, so concurrent release / ingest calls cannot race into double-decrement or stale zero-ref observations.
- Retry paths for `StyledGeneration` / `ProcessingTask` explicitly release prior-attempt blobs before re-enqueue to avoid blob leaks on repeated failures.
- `card_pack.import_count` is now updated under `SELECT ... FOR UPDATE`, closing the TOCTOU window between "I was at zero when I checked" and the hard-delete commit. A new `ck_card_pack_import_count_nonneg` CHECK constraint defends against underflow.
- New Celery-beat reap jobs scan `styled_generations` and `processing_tasks` every hour for rows stuck in `PROCESSING` past their `lease_expires_at` and flip them to `FAILED`.
- A weekly orphan-file sweep on local storage reconciles bytes on disk against `blobs.blob_hash`, removing anything not in the registry. (S3 storage is covered by the existing `gc_sweep` task.)
- `SECRET_KEY` now has a production-environment validator that rejects the dev default on `ENV=production`.
- N+1 fix in the wardrobe list endpoints (single query now loads `wardrobe_items` with joinedload; previously each item fetched its `clothing_items` row individually).
- `files.py` card-pack cover route gained an auth guard that returns 404 for `DRAFT` / `ARCHIVED` packs to non-owners — the previous route leaked DRAFT cover bytes by blob hash.

