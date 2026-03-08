"""
Module 3: Wardrobe & WardrobeItem models.
- Deleting a wardrobe only removes wardrobe_items; clothing_items are unchanged.
"""
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
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class Wardrobe(Base):
    __tablename__ = "wardrobes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name = Column(String(100), nullable=False)
    type = Column(String(20), nullable=False, default="REGULAR")
    description = Column(Text, nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        CheckConstraint("type IN ('REGULAR', 'VIRTUAL')", name="ck_wardrobe_type"),
        Index("idx_wardrobes_user", "user_id"),
    )

    items = relationship(
        "WardrobeItem",
        back_populates="wardrobe",
        cascade="all, delete-orphan",
        order_by="WardrobeItem.display_order, WardrobeItem.added_at",
    )


class WardrobeItem(Base):
    """Junction: which clothing item is in which wardrobe. No duplication of clothing data."""
    __tablename__ = "wardrobe_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    wardrobe_id = Column(
        UUID(as_uuid=True),
        ForeignKey("wardrobes.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    added_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    display_order = Column(Integer, nullable=True)

    __table_args__ = (
        Index("idx_wardrobe_items_wardrobe", "wardrobe_id"),
        Index("uq_wardrobe_item", "wardrobe_id", "clothing_item_id", unique=True),
    )

    wardrobe = relationship("Wardrobe", back_populates="items")
    clothing_item = relationship("ClothingItem", backref="wardrobe_entries")
