-- 初始化数据库 Schema（Module 2 所需部分）
-- 完整 Schema 见 documents/BACKEND_ARCHITECTURE.md
-- TODO: 与队友确认 - 是否使用 Alembic，由谁维护迁移

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
CREATE INDEX IF NOT EXISTS idx_clothing_final_tags ON clothing_items USING GIN(final_tags);
