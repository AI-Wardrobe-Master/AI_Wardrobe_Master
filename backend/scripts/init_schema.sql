-- 初始化数据库 Schema（Module 2 所需部分）
-- 完整 Schema 见 documents/BACKEND_ARCHITECTURE.md
-- TODO: 与队友确认 - 是否使用 Alembic，由谁维护迁移

CREATE EXTENSION IF NOT EXISTS pgcrypto;

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
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (
        status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED')
    ),
    progress INTEGER DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_processing_tasks_item_created
ON processing_tasks(clothing_item_id, created_at);

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
