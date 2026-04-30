import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
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
    display_name = Column(String(100), nullable=False)
    brand_name = Column(String(120), nullable=True)
    bio = Column(Text, nullable=True)
    avatar_url = Column(Text, nullable=True)
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
    wardrobe_id = Column(
        UUID(as_uuid=True),
        ForeignKey("wardrobes.id", ondelete="SET NULL"),
        nullable=True,
        unique=True,
    )
    share_id = Column(String(64), nullable=True, unique=True)
    import_count = Column(Integer, nullable=False, default=0)
    view_count = Column(Integer, nullable=False, server_default="0", default=0)
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
    linked_wardrobe = relationship("Wardrobe", foreign_keys=[wardrobe_id], uselist=False)


class CardPackItem(Base):
    __tablename__ = "card_pack_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    card_pack_id = Column(
        UUID(as_uuid=True),
        ForeignKey("card_packs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    __table_args__ = (
        Index(
            "uq_card_pack_items_pack_clothing_item",
            "card_pack_id",
            "clothing_item_id",
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
    clothing_item = relationship("ClothingItem", backref="pack_entries")
