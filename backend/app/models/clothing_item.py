import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    ARRAY,
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class ClothingItem(Base):
    __tablename__ = "clothing_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    source = Column(String(20), nullable=False, default="OWNED")

    predicted_tags = Column(JSONB, nullable=False, default=[])
    final_tags = Column(JSONB, nullable=False, default=[])
    is_confirmed = Column(Boolean, default=False)

    name = Column(String(200))
    description = Column(Text)
    custom_tags = Column(ARRAY(String), default=[])

    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        CheckConstraint("source IN ('OWNED', 'IMPORTED')", name="ck_source"),
    )

    images = relationship(
        "Image", back_populates="clothing_item", cascade="all, delete-orphan"
    )
    model_3d = relationship(
        "Model3D",
        back_populates="clothing_item",
        uselist=False,
        cascade="all, delete-orphan",
    )
    processing_tasks = relationship(
        "ProcessingTask", back_populates="clothing_item", cascade="all, delete-orphan"
    )


class Image(Base):
    __tablename__ = "images"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    clothing_item_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    image_type = Column(String(20), nullable=False)
    storage_path = Column(Text, nullable=False)
    angle = Column(Integer, nullable=True)
    file_size = Column(BigInteger, nullable=True)
    mime_type = Column(String(50), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint(
            "image_type IN ('ORIGINAL_FRONT','ORIGINAL_BACK','PROCESSED_FRONT',"
            "'PROCESSED_BACK','ANGLE_VIEW')",
            name="ck_image_type",
        ),
        CheckConstraint(
            "angle IS NULL OR angle IN (0,45,90,135,180,225,270,315)",
            name="ck_angle",
        ),
    )

    clothing_item = relationship("ClothingItem", back_populates="images")


class Model3D(Base):
    __tablename__ = "models_3d"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    clothing_item_id = Column(UUID(as_uuid=True), unique=True, nullable=False)
    model_format = Column(String(10), nullable=False, default="glb")
    storage_path = Column(Text, nullable=False)
    vertex_count = Column(Integer, nullable=True)
    face_count = Column(Integer, nullable=True)
    file_size = Column(BigInteger, nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    clothing_item = relationship("ClothingItem", back_populates="model_3d")


class ProcessingTask(Base):
    __tablename__ = "processing_tasks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    clothing_item_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    task_type = Column(String(30), nullable=False)
    status = Column(String(20), nullable=False, default="PENDING")
    progress = Column(Integer, default=0)
    error_message = Column(Text, nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint(
            "task_type IN ('BACKGROUND_REMOVAL','3D_GENERATION',"
            "'ANGLE_RENDERING','FULL_PIPELINE')",
            name="ck_task_type",
        ),
        CheckConstraint(
            "status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_task_status",
        ),
        CheckConstraint("progress BETWEEN 0 AND 100", name="ck_progress"),
    )

    clothing_item = relationship("ClothingItem", back_populates="processing_tasks")
