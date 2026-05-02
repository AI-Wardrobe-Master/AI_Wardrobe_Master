-- 初始化数据库 Schema（Module 2 所需部分）
-- 完整 Schema 见 documents/BACKEND_ARCHITECTURE.md
-- TODO: 与队友确认 - 是否使用 Alembic，由谁维护迁移

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS blobs (
    blob_hash VARCHAR(64) PRIMARY KEY,
    byte_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    ref_count INTEGER NOT NULL DEFAULT 0 CHECK (ref_count >= 0),
    first_seen_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_referenced_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    pending_delete_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_blobs_pending_delete
ON blobs(pending_delete_at)
WHERE pending_delete_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('CONSUMER', 'CREATOR')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS clothing_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source VARCHAR(20) NOT NULL CHECK (source IN ('OWNED', 'IMPORTED')),
    predicted_tags JSONB NOT NULL DEFAULT '[]',
    final_tags JSONB NOT NULL DEFAULT '[]',
    is_confirmed BOOLEAN DEFAULT FALSE,
    name VARCHAR(200),
    description TEXT,
    custom_tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_clothing_user ON clothing_items(user_id);
CREATE INDEX IF NOT EXISTS idx_clothing_source ON clothing_items(source);
CREATE INDEX IF NOT EXISTS idx_clothing_user_source ON clothing_items(user_id, source);
CREATE INDEX IF NOT EXISTS idx_clothing_user_created ON clothing_items(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_clothing_final_tags ON clothing_items USING GIN(final_tags);
CREATE INDEX IF NOT EXISTS idx_clothing_custom_tags ON clothing_items USING GIN(custom_tags);

CREATE TABLE IF NOT EXISTS images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    image_type VARCHAR(20) NOT NULL CHECK (
        image_type IN (
            'ORIGINAL_FRONT',
            'ORIGINAL_BACK',
            'PROCESSED_FRONT',
            'PROCESSED_BACK',
            'ANGLE_VIEW'
        )
    ),
    storage_path TEXT NOT NULL,
    angle INTEGER,
    file_size BIGINT,
    mime_type VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_angle CHECK (angle IS NULL OR angle IN (0, 45, 90, 135, 180, 225, 270, 315))
);

CREATE INDEX IF NOT EXISTS idx_images_clothing ON images(clothing_item_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_images_item_type_null_angle
ON images(clothing_item_id, image_type)
WHERE angle IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_images_item_type_angle_not_null
ON images(clothing_item_id, image_type, angle)
WHERE angle IS NOT NULL;

CREATE TABLE IF NOT EXISTS models_3d (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clothing_item_id UUID UNIQUE NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    model_format VARCHAR(10) NOT NULL DEFAULT 'glb' CHECK (model_format IN ('glb')),
    storage_path TEXT NOT NULL,
    vertex_count INTEGER,
    face_count INTEGER,
    file_size BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS processing_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    task_type VARCHAR(30) NOT NULL CHECK (
        task_type IN (
            'CLASSIFICATION',
            'BACKGROUND_REMOVAL',
            '3D_GENERATION',
            'ANGLE_RENDERING',
            'FULL_PIPELINE'
        )
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

CREATE INDEX IF NOT EXISTS idx_processing_tasks_item_created
ON processing_tasks(clothing_item_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_processing_tasks_active_item
ON processing_tasks(clothing_item_id)
WHERE status IN ('PENDING', 'PROCESSING');

CREATE TABLE IF NOT EXISTS outfit_preview_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    person_image_blob_hash VARCHAR(64) NOT NULL REFERENCES blobs(blob_hash),
    person_view_type VARCHAR(20) NOT NULL CHECK (person_view_type IN ('FULL_BODY', 'UPPER_BODY')),
    garment_categories JSONB NOT NULL DEFAULT '[]',
    input_count INTEGER NOT NULL DEFAULT 0 CHECK (input_count >= 0),
    prompt_template_key VARCHAR(100) NOT NULL,
    provider_name VARCHAR(50) NOT NULL DEFAULT 'DashScope',
    provider_model VARCHAR(100) NOT NULL DEFAULT 'wan2.6-image',
    provider_job_id VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED')),
    preview_image_blob_hash VARCHAR(64) REFERENCES blobs(blob_hash),
    error_code VARCHAR(100),
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_outfit_preview_tasks_user_created
ON outfit_preview_tasks(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_outfit_preview_tasks_status_created
ON outfit_preview_tasks(status, created_at);

CREATE TABLE IF NOT EXISTS outfit_preview_task_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES outfit_preview_tasks(id) ON DELETE CASCADE,
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    garment_category VARCHAR(20) NOT NULL CHECK (garment_category IN ('TOP', 'BOTTOM', 'SHOES')),
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    garment_image_blob_hash VARCHAR(64) NOT NULL REFERENCES blobs(blob_hash),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(task_id, clothing_item_id),
    UNIQUE(task_id, garment_category)
);
CREATE INDEX IF NOT EXISTS idx_outfit_preview_task_items_task_order
ON outfit_preview_task_items(task_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_outfit_preview_task_items_task
ON outfit_preview_task_items(task_id);
CREATE INDEX IF NOT EXISTS idx_outfit_preview_task_items_clothing_item
ON outfit_preview_task_items(clothing_item_id);

CREATE TABLE IF NOT EXISTS outfits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    preview_task_id UUID UNIQUE REFERENCES outfit_preview_tasks(id) ON DELETE SET NULL,
    name VARCHAR(120),
    preview_image_blob_hash VARCHAR(64) NOT NULL REFERENCES blobs(blob_hash),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_outfits_user_created
ON outfits(user_id, created_at);

CREATE TABLE IF NOT EXISTS outfit_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    outfit_id UUID NOT NULL REFERENCES outfits(id) ON DELETE CASCADE,
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(outfit_id, clothing_item_id)
);
CREATE INDEX IF NOT EXISTS idx_outfit_items_outfit
ON outfit_items(outfit_id);
CREATE INDEX IF NOT EXISTS idx_outfit_items_clothing_item
ON outfit_items(clothing_item_id);

-- Module 3: Wardrobes (delete wardrobe only removes links, not clothing_items)
CREATE TABLE IF NOT EXISTS wardrobes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'REGULAR' CHECK (type IN ('REGULAR', 'VIRTUAL')),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_wardrobes_user ON wardrobes(user_id);

CREATE TABLE IF NOT EXISTS wardrobe_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wardrobe_id UUID NOT NULL REFERENCES wardrobes(id) ON DELETE CASCADE,
    clothing_item_id UUID NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    display_order INTEGER,
    UNIQUE(wardrobe_id, clothing_item_id)
);
CREATE INDEX IF NOT EXISTS idx_wardrobe_items_wardrobe ON wardrobe_items(wardrobe_id);
CREATE INDEX IF NOT EXISTS idx_wardrobe_items_clothing ON wardrobe_items(clothing_item_id);
