import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class OutfitPreviewTask(Base):
    __tablename__ = "outfit_preview_tasks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    person_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
    person_view_type = Column(String(20), nullable=False)
    garment_categories = Column(JSONB, nullable=False, default=list)
    input_count = Column(Integer, nullable=False, default=0)
    prompt_template_key = Column(String(100), nullable=False)
    provider_name = Column(String(50), nullable=False, default="DashScope")
    provider_model = Column(String(100), nullable=False, default="wan2.6-image")
    provider_job_id = Column(String(255), nullable=True)
    status = Column(String(20), nullable=False, default="PENDING")
    preview_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=True)
    error_code = Column(String(100), nullable=True)
    error_message = Column(Text, nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint(
            "person_view_type IN ('FULL_BODY','UPPER_BODY')",
            name="ck_outfit_preview_person_view_type",
        ),
        CheckConstraint(
            "status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_outfit_preview_status",
        ),
        CheckConstraint("input_count >= 0", name="ck_outfit_preview_input_count"),
        Index(
            "idx_outfit_preview_tasks_user_created",
            "user_id",
            "created_at",
        ),
        Index(
            "idx_outfit_preview_tasks_status_created",
            "status",
            "created_at",
        ),
    )

    items = relationship(
        "OutfitPreviewTaskItem",
        back_populates="task",
        cascade="all, delete-orphan",
        order_by="OutfitPreviewTaskItem.sort_order",
    )
    saved_outfit = relationship(
        "Outfit",
        back_populates="preview_task",
        uselist=False,
    )


class OutfitPreviewTaskItem(Base):
    __tablename__ = "outfit_preview_task_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    task_id = Column(
        UUID(as_uuid=True),
        ForeignKey("outfit_preview_tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    garment_category = Column(String(20), nullable=False)
    sort_order = Column(Integer, nullable=False, default=0)
    garment_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint(
            "garment_category IN ('TOP','BOTTOM','SHOES')",
            name="ck_outfit_preview_task_item_garment_category",
        ),
        CheckConstraint("sort_order >= 0", name="ck_outfit_preview_task_item_sort"),
        UniqueConstraint("task_id", "clothing_item_id", name="uq_outfit_preview_task_items_task_clothing_item"),
        UniqueConstraint("task_id", "garment_category", name="uq_outfit_preview_task_items_task_category"),
        Index(
            "idx_outfit_preview_task_items_task_order",
            "task_id",
            "sort_order",
        ),
    )

    task = relationship("OutfitPreviewTask", back_populates="items")
    clothing_item = relationship("ClothingItem")


class Outfit(Base):
    __tablename__ = "outfits"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    preview_task_id = Column(
        UUID(as_uuid=True),
        ForeignKey("outfit_preview_tasks.id", ondelete="SET NULL"),
        nullable=True,
        unique=True,
    )
    name = Column(String(120), nullable=True)
    preview_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        Index("idx_outfits_user_created", "user_id", "created_at"),
    )

    preview_task = relationship("OutfitPreviewTask", back_populates="saved_outfit")
    items = relationship(
        "OutfitItem",
        back_populates="outfit",
        cascade="all, delete-orphan",
        order_by="OutfitItem.created_at",
    )


class OutfitItem(Base):
    __tablename__ = "outfit_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    outfit_id = Column(
        UUID(as_uuid=True),
        ForeignKey("outfits.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        UniqueConstraint("outfit_id", "clothing_item_id", name="uq_outfit_items_outfit_clothing_item"),
        Index("idx_outfit_items_outfit", "outfit_id"),
        Index("idx_outfit_items_clothing_item", "clothing_item_id"),
    )

    outfit = relationship("Outfit", back_populates="items")
    clothing_item = relationship("ClothingItem")
