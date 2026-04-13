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
- `creator_items.py` reuses the clothing pipeline but enforces creator ownership and catalog visibility.
- `creators.py` handles public creator browse plus authenticated self-service profile and dashboard access.
- `card_packs.py` owns draft/publish/archive/delete transitions and public share reads.
- `imports.py` is a transactional route surface and must delegate write orchestration to a service.
- `outfit_preview.py` is isolated from clothing processing and owns preview task creation, polling, and save-to-outfit.
- `outfits.py` only manages saved outfit metadata and retrieval. It does not behave like a generation task controller.

### Data Model Overrides

- Imported-item provenance is stored on `clothing_items` via origin fields, not in a standalone `provenance` table.
- `wardrobes` must support `is_system_managed` and `system_key`, with `DEFAULT_VIRTUAL_IMPORTED` reserved for the auto-created imported-content wardrobe.
- Creator business data should live in `creator_profiles` keyed by `user_id`, with explicit `PENDING / ACTIVE / SUSPENDED` lifecycle state.
- Import flow requires `import_histories` plus `import_history_items` so that cloned imported items can be traced back to both pack and source item.
- Outfit preview is a separate domain modeled by `outfit_preview_tasks` and `outfit_preview_task_items`.
- `outfits` represent confirmed saved results and may reference `preview_task_id`; they should not also serve as asynchronous processing records.

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
    brand_name VARCHAR(200),
    website_url TEXT,
    social_links JSONB,  -- {platform: url}
    follower_count INTEGER DEFAULT 0,
    pack_count INTEGER DEFAULT 0,
    is_verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

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

- API writes are short-lived: store original uploads, create `clothing_items`, create `processing_tasks(PENDING)`, then enqueue Celery.
- Celery workers claim a task atomically before moving it to `PROCESSING`.
- Worker failures mark the task `FAILED`, keep original uploads, and remove all derived database records and files.
- Retry creates a new task row instead of mutating the failed task, preserving audit history.

