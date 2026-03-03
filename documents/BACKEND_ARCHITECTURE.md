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
│   │       ├── outfit.py            # Outfit endpoints
│   │       ├── card_pack.py         # Card pack endpoints
│   │       ├── creator.py           # Creator endpoints
│   │       ├── import_ops.py        # Import operations
│   │       └── image.py             # Image processing endpoints
│   │
│   ├── models/                      # SQLAlchemy models
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── clothing_item.py
│   │   ├── wardrobe.py
│   │   ├── outfit.py
│   │   ├── card_pack.py
│   │   └── associations.py          # Many-to-many tables
│   │
│   ├── schemas/                     # Pydantic schemas
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── clothing_item.py
│   │   ├── wardrobe.py
│   │   ├── outfit.py
│   │   └── card_pack.py
│   │
│   ├── crud/                        # CRUD operations
│   │   ├── __init__.py
│   │   ├── base.py                  # Base CRUD class
│   │   ├── clothing.py
│   │   ├── wardrobe.py
│   │   └── outfit.py
│   │
│   ├── services/                    # Business logic services
│   │   ├── __init__.py
│   │   ├── auth_service.py          # Authentication logic
│   │   ├── storage_service.py       # S3/MinIO/Local storage
│   │   ├── image_service.py         # Image processing
│   │   ├── ai_service.py            # AI classification
│   │   └── search_service.py        # Search functionality
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

-- provenance table
CREATE TABLE provenance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clothing_item_id UUID UNIQUE NOT NULL REFERENCES clothing_items(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES users(id),
    creator_name VARCHAR(100) NOT NULL,
    card_pack_id UUID,
    card_pack_name VARCHAR(200),
    imported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    import_source TEXT
);

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

## SQLAlchemy Models Example

```python
# app/models/clothing_item.py
from sqlalchemy import Column, String, Boolean, ARRAY, ForeignKey, DateTime
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid

from app.db.base import Base

class ClothingItem(Base):
    __tablename__ = "clothing_items"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    source = Column(String(20), nullable=False)
    
    # Tag-based classification
    predicted_tags = Column(JSONB, nullable=False, default=[])  # Immutable AI predictions
    final_tags = Column(JSONB, nullable=False, default=[])      # User-confirmed tags
    is_confirmed = Column(Boolean, default=False)
    
    # Metadata
    name = Column(String(200))
    description = Column(String)
    custom_tags = Column(ARRAY(String), default=[])  # User-defined freeform tags
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    user = relationship("User", back_populates="clothing_items")
    images = relationship("Image", back_populates="clothing_item", cascade="all, delete-orphan")
    provenance = relationship("Provenance", back_populates="clothing_item", uselist=False)
    wardrobes = relationship("Wardrobe", secondary="wardrobe_items", back_populates="items")

# Tag structure example:
# predicted_tags = [
#     {"key": "category", "value": "T_SHIRT"},
#     {"key": "color", "value": "blue"},
#     {"key": "pattern", "value": "striped"}
# ]
```

---

## Pydantic Schemas Example

```python
# app/schemas/clothing_item.py
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
from datetime import datetime
from uuid import UUID
from enum import Enum

class ItemSource(str, Enum):
    OWNED = "OWNED"
    IMPORTED = "IMPORTED"

class ClothingType(str, Enum):
    # Tops
    T_SHIRT = "T_SHIRT"
    SHIRT = "SHIRT"
    BLOUSE = "BLOUSE"
    POLO = "POLO"
    TANK_TOP = "TANK_TOP"
    SWEATER = "SWEATER"
    HOODIE = "HOODIE"
    SWEATSHIRT = "SWEATSHIRT"
    CARDIGAN = "CARDIGAN"
    
    # Bottoms
    JEANS = "JEANS"
    TROUSERS = "TROUSERS"
    SHORTS = "SHORTS"
    SKIRT = "SKIRT"
    LEGGINGS = "LEGGINGS"
    SWEATPANTS = "SWEATPANTS"
    
    # Outerwear
    JACKET = "JACKET"
    COAT = "COAT"
    BLAZER = "BLAZER"
    PUFFER = "PUFFER"
    WIND_BREAKER = "WIND_BREAKER"
    VEST = "VEST"
    
    # Full Body
    DRESS = "DRESS"
    JUMPSUIT = "JUMPSUIT"
    ROMPER = "ROMPER"
    
    # Footwear
    SNEAKERS = "SNEAKERS"
    BOOTS = "BOOTS"
    SANDALS = "SANDALS"
    DRESS_SHOES = "DRESS_SHOES"
    HEELS = "HEELS"
    SLIPPERS = "SLIPPERS"
    
    # Accessories
    HAT = "HAT"
    SCARF = "SCARF"
    BELT = "BELT"
    
    # Fallback
    OTHER = "OTHER"

class Tag(BaseModel):
    """Tag structure: {key: string, value: string}"""
    key: str = Field(..., description="Tag key (e.g., 'category', 'color', 'pattern')")
    value: str = Field(..., description="Tag value (e.g., 'T_SHIRT', 'blue', 'striped')")

class ClothingItemBase(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    customTags: List[str] = Field(default_factory=list, description="User-defined freeform tags")

class ClothingItemCreate(ClothingItemBase):
    pass

class ClothingItemUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    finalTags: Optional[List[Tag]] = Field(None, description="User-confirmed tags (replaces all)")
    isConfirmed: Optional[bool] = None
    customTags: Optional[List[str]] = None

class ClothingItemInDB(ClothingItemBase):
    model_config = ConfigDict(from_attributes=True)
    
    id: UUID
    user_id: UUID
    source: ItemSource
    predicted_tags: List[Tag] = Field(default_factory=list, description="Immutable AI predictions")
    final_tags: List[Tag] = Field(default_factory=list, description="User-confirmed tags")
    is_confirmed: bool
    created_at: datetime
    updated_at: datetime

class ClothingItemResponse(ClothingItemInDB):
    images: List["ImageResponse"] = []
    provenance: Optional["ProvenanceResponse"] = None
```

---

## Storage Service (S3/MinIO/Local)

```python
# app/services/storage_service.py
from abc import ABC, abstractmethod
from typing import BinaryIO, Optional
import boto3
from pathlib import Path
import shutil
from app.core.config import settings

class StorageService(ABC):
    @abstractmethod
    async def upload_file(self, file: BinaryIO, path: str) -> str:
        """Upload file and return storage path"""
        pass
    
    @abstractmethod
    async def download_file(self, path: str) -> bytes:
        """Download file from storage"""
        pass
    
    @abstractmethod
    async def delete_file(self, path: str) -> bool:
        """Delete file from storage"""
        pass
    
    @abstractmethod
    def get_url(self, path: str) -> str:
        """Get accessible URL for file"""
        pass

class S3StorageService(StorageService):
    def __init__(self):
        self.s3_client = boto3.client(
            's3',
            endpoint_url=settings.S3_ENDPOINT,
            aws_access_key_id=settings.S3_ACCESS_KEY,
            aws_secret_access_key=settings.S3_SECRET_KEY,
            region_name=settings.S3_REGION
        )
        self.bucket = settings.S3_BUCKET
    
    async def upload_file(self, file: BinaryIO, path: str) -> str:
        self.s3_client.upload_fileobj(file, self.bucket, path)
        return path
    
    async def download_file(self, path: str) -> bytes:
        response = self.s3_client.get_object(Bucket=self.bucket, Key=path)
        return response['Body'].read()
    
    async def delete_file(self, path: str) -> bool:
        self.s3_client.delete_object(Bucket=self.bucket, Key=path)
        return True
    
    def get_url(self, path: str) -> str:
        if settings.S3_PUBLIC_URL:
            return f"{settings.S3_PUBLIC_URL}/{path}"
        return self.s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': self.bucket, 'Key': path},
            ExpiresIn=3600
        )

class LocalStorageService(StorageService):
    def __init__(self):
        self.base_path = Path(settings.LOCAL_STORAGE_PATH)
        self.base_path.mkdir(parents=True, exist_ok=True)
    
    async def upload_file(self, file: BinaryIO, path: str) -> str:
        file_path = self.base_path / path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(file_path, 'wb') as f:
            shutil.copyfileobj(file, f)
        return path
    
    async def download_file(self, path: str) -> bytes:
        file_path = self.base_path / path
        with open(file_path, 'rb') as f:
            return f.read()
    
    async def delete_file(self, path: str) -> bool:
        file_path = self.base_path / path
        if file_path.exists():
            file_path.unlink()
            return True
        return False
    
    def get_url(self, path: str) -> str:
        return f"{settings.API_BASE_URL}/files/{path}"

# Factory function
def get_storage_service() -> StorageService:
    if settings.STORAGE_TYPE == "s3":
        return S3StorageService()
    elif settings.STORAGE_TYPE == "local":
        return LocalStorageService()
    else:
        raise ValueError(f"Unknown storage type: {settings.STORAGE_TYPE}")
```

---

## Configuration

```python
# app/core/config.py
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # API
    API_V1_STR: str = "/api/v1"
    PROJECT_NAME: str = "AI Wardrobe Master"
    
    # Database
    POSTGRES_SERVER: str
    POSTGRES_USER: str
    POSTGRES_PASSWORD: str
    POSTGRES_DB: str
    POSTGRES_PORT: str = "5432"
    
    @property
    def DATABASE_URL(self) -> str:
        return f"postgresql://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_SERVER}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
    
    # Storage
    STORAGE_TYPE: str = "local"  # "s3" or "local"
    
    # S3/MinIO
    S3_ENDPOINT: Optional[str] = None
    S3_ACCESS_KEY: Optional[str] = None
    S3_SECRET_KEY: Optional[str] = None
    S3_BUCKET: Optional[str] = None
    S3_REGION: str = "us-east-1"
    S3_PUBLIC_URL: Optional[str] = None
    
    # Local Storage
    LOCAL_STORAGE_PATH: str = "./storage"
    
    # Security
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
    
    # CORS
    BACKEND_CORS_ORIGINS: list = ["*"]
    
    class Config:
        env_file = ".env"
        case_sensitive = True

settings = Settings()
```

---

## API Endpoint Example

```python
# app/api/v1/clothing.py
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID

from app.api import deps
from app.schemas.clothing_item import ClothingItemCreate, ClothingItemResponse
from app.crud import clothing as crud_clothing
from app.services.storage_service import get_storage_service
from app.services.image_service import ImageService
from app.services.ai_service import AIService

router = APIRouter()

@router.post("/", response_model=ClothingItemResponse, status_code=201)
async def create_clothing_item(
    *,
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_user),
    front_image: UploadFile = File(...),
    back_image: UploadFile = File(...),
    name: str = None,
    description: str = None
):
    """
    Create new clothing item with image upload
    """
    storage = get_storage_service()
    image_service = ImageService(storage)
    ai_service = AIService()
    
    # Process images
    front_processed = await image_service.process_image(front_image)
    back_processed = await image_service.process_image(back_image)
    
    # AI classification - returns Tag[]
    classification = await ai_service.classify_clothing(front_processed)
    
    # Create clothing item
    item_data = ClothingItemCreate(
        name=name,
        description=description,
        customTags=custom_tags or []
    )
    
    clothing_item = await crud_clothing.create_with_images(
        db=db,
        user_id=current_user.id,
        obj_in=item_data,
        front_image=front_processed,
        back_image=back_processed,
        predicted_tags=classification["predictedTags"]  # Tag[] from AI
    )
    
    return clothing_item

@router.get("/", response_model=List[ClothingItemResponse])
async def list_clothing_items(
    db: Session = Depends(deps.get_db),
    current_user = Depends(deps.get_current_user),
    skip: int = 0,
    limit: int = 20,
    source: Optional[str] = None,
    tag_key: Optional[str] = None,
    tag_value: Optional[str] = None
):
    """
    List user's clothing items with filters
    Search uses final_tags only (not predicted_tags)
    """
    items = crud_clothing.get_multi_by_user(
        db=db,
        user_id=current_user.id,
        skip=skip,
        limit=limit,
        source=source,
        type=type
    )
    return items
```

---

## Docker Compose Setup

```yaml
# docker-compose.yml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: wardrobe_user
      POSTGRES_PASSWORD: wardrobe_pass
      POSTGRES_DB: wardrobe_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
  
  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data
  
  backend:
    build: .
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
    volumes:
      - ./backend:/app
    ports:
      - "8000:8000"
    environment:
      - POSTGRES_SERVER=postgres
      - POSTGRES_USER=wardrobe_user
      - POSTGRES_PASSWORD=wardrobe_pass
      - POSTGRES_DB=wardrobe_db
      - STORAGE_TYPE=s3
      - S3_ENDPOINT=http://minio:9000
      - S3_ACCESS_KEY=minioadmin
      - S3_SECRET_KEY=minioadmin
      - S3_BUCKET=wardrobe-images
    depends_on:
      - postgres
      - minio

volumes:
  postgres_data:
  minio_data:
```

---

## Requirements.txt

```txt
fastapi==0.109.0
uvicorn[standard]==0.27.0
sqlalchemy==2.0.25
alembic==1.13.1
psycopg2-binary==2.9.9
pydantic==2.5.3
pydantic-settings==2.1.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6
boto3==1.34.34
pillow==10.2.0
opencv-python-headless==4.9.0.80
pytest==7.4.4
pytest-asyncio==0.23.3
httpx==0.26.0
```

---

## Next Steps

1. Setup PostgreSQL database
2. Configure S3/MinIO or local storage
3. Implement authentication
4. Build CRUD operations
5. Add image processing pipeline
6. Integrate AI classification (optional)
7. Write tests
8. Deploy with Docker
