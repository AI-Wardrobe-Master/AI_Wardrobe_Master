import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    ARRAY,
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    text as sql_text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class CreatorProfile(Base):
    __tablename__ = "creator_profiles"

    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    status = Column(String(20), nullable=False, default="ACTIVE")
    display_name = Column(String(120), nullable=False)
    brand_name = Column(String(120), nullable=True)
    bio = Column(Text, nullable=True)
    avatar_storage_path = Column(Text, nullable=True)
    website_url = Column(Text, nullable=True)
    social_links = Column(JSONB, nullable=False, default={})
    is_verified = Column(Boolean, nullable=False, default=False)
    verified_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('PENDING','ACTIVE','SUSPENDED')",
            name="ck_creator_profile_status",
        ),
    )


class CreatorItem(Base):
    __tablename__ = "creator_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    catalog_visibility = Column(String(20), nullable=False, default="PACK_ONLY")
    processing_status = Column(String(20), nullable=False, default="PENDING")
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
        CheckConstraint(
            "catalog_visibility IN ('PRIVATE','PACK_ONLY','PUBLIC')",
            name="ck_creator_item_visibility",
        ),
        CheckConstraint(
            "processing_status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_creator_item_processing_status",
        ),
        Index("idx_creator_items_creator_created", "creator_id", "created_at"),
        Index(
            "idx_creator_items_creator_visibility",
            "creator_id",
            "catalog_visibility",
        ),
        Index(
            "idx_creator_items_final_tags",
            "final_tags",
            postgresql_using="gin",
        ),
        Index(
            "idx_creator_items_custom_tags",
            "custom_tags",
            postgresql_using="gin",
        ),
    )

    images = relationship(
        "CreatorItemImage",
        back_populates="creator_item",
        cascade="all, delete-orphan",
    )
    model_3d = relationship(
        "CreatorItemModel3D",
        back_populates="creator_item",
        uselist=False,
        cascade="all, delete-orphan",
    )
    processing_tasks = relationship(
        "CreatorProcessingTask",
        back_populates="creator_item",
        cascade="all, delete-orphan",
    )


class CreatorItemImage(Base):
    __tablename__ = "creator_item_images"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("creator_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    image_type = Column(String(20), nullable=False)
    blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
    angle = Column(Integer, nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint(
            "image_type IN ('ORIGINAL_FRONT','ORIGINAL_BACK','PROCESSED_FRONT',"
            "'PROCESSED_BACK','ANGLE_VIEW')",
            name="ck_creator_item_image_type",
        ),
        CheckConstraint(
            "angle IS NULL OR angle IN (0,45,90,135,180,225,270,315)",
            name="ck_creator_item_angle",
        ),
        Index(
            "uq_creator_item_images_null_angle",
            "creator_item_id",
            "image_type",
            unique=True,
            postgresql_where=sql_text("angle IS NULL"),
        ),
        Index(
            "uq_creator_item_images_angle_not_null",
            "creator_item_id",
            "image_type",
            "angle",
            unique=True,
            postgresql_where=sql_text("angle IS NOT NULL"),
        ),
    )

    creator_item = relationship("CreatorItem", back_populates="images")


class CreatorItemModel3D(Base):
    __tablename__ = "creator_models_3d"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("creator_items.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    model_format = Column(String(10), nullable=False, default="glb")
    blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
    vertex_count = Column(Integer, nullable=True)
    face_count = Column(Integer, nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint("model_format IN ('glb')", name="ck_creator_model_format"),
    )

    creator_item = relationship("CreatorItem", back_populates="model_3d")


class CreatorProcessingTask(Base):
    __tablename__ = "creator_processing_tasks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("creator_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    task_type = Column(String(30), nullable=False)
    attempt_no = Column(Integer, nullable=False, default=1)
    retry_of_task_id = Column(
        UUID(as_uuid=True),
        ForeignKey("creator_processing_tasks.id", ondelete="SET NULL"),
        nullable=True,
    )
    status = Column(String(20), nullable=False, default="PENDING")
    progress = Column(Integer, default=0)
    error_message = Column(Text, nullable=True)
    worker_id = Column(String(255), nullable=True)
    lease_expires_at = Column(DateTime(timezone=True), nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        CheckConstraint(
            "task_type IN ('CLASSIFICATION','BACKGROUND_REMOVAL','3D_GENERATION',"
            "'ANGLE_RENDERING','FULL_PIPELINE')",
            name="ck_creator_task_type",
        ),
        CheckConstraint("attempt_no >= 1", name="ck_creator_attempt_no"),
        CheckConstraint(
            "status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_creator_task_status",
        ),
        CheckConstraint("progress BETWEEN 0 AND 100", name="ck_creator_progress"),
        Index(
            "idx_creator_processing_tasks_item_created",
            "creator_item_id",
            "created_at",
        ),
        Index(
            "uq_creator_processing_tasks_active_item",
            "creator_item_id",
            unique=True,
            postgresql_where=sql_text("status IN ('PENDING','PROCESSING')"),
        ),
    )

    creator_item = relationship("CreatorItem", back_populates="processing_tasks")
    retry_of_task = relationship("CreatorProcessingTask", remote_side=[id], uselist=False)


class CardPack(Base):
    __tablename__ = "card_packs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name = Column(String(160), nullable=False)
    description = Column(Text, nullable=True)
    pack_type = Column(String(40), nullable=False, default="CLOTHING_COLLECTION")
    status = Column(String(20), nullable=False, default="DRAFT")
    cover_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=True)
    share_id = Column(String(64), nullable=True, unique=True)
    import_count = Column(Integer, nullable=False, default=0)
    published_at = Column(DateTime(timezone=True), nullable=True)
    archived_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        CheckConstraint(
            "pack_type IN ('CLOTHING_COLLECTION')",
            name="ck_card_pack_type",
        ),
        CheckConstraint(
            "status IN ('DRAFT','PUBLISHED','ARCHIVED')",
            name="ck_card_pack_status",
        ),
        Index("idx_card_pack_creator_status", "creator_id", "status"),
        Index("idx_card_pack_creator_created", "creator_id", "created_at"),
    )

    items = relationship(
        "CardPackItem",
        back_populates="card_pack",
        cascade="all, delete-orphan",
        order_by="CardPackItem.sort_order, CardPackItem.created_at",
    )


class CardPackItem(Base):
    __tablename__ = "card_pack_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    card_pack_id = Column(
        UUID(as_uuid=True),
        ForeignKey("card_packs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    creator_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("creator_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        Index(
            "uq_card_pack_items_pack_creator_item",
            "card_pack_id",
            "creator_item_id",
            unique=True,
        ),
        Index(
            "uq_card_pack_items_pack_sort_order",
            "card_pack_id",
            "sort_order",
            unique=True,
        ),
        Index("idx_card_pack_items_pack", "card_pack_id"),
    )

    card_pack = relationship("CardPack", back_populates="items")
    creator_item = relationship("CreatorItem", backref="pack_items")
