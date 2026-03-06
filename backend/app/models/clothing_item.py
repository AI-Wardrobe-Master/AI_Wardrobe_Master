"""
ClothingItem model - supports Module 2 tag structure (predicted_tags, final_tags)
"""
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, ARRAY, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from app.db.base import Base


class ClothingItem(Base):
    __tablename__ = "clothing_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    source = Column(String(20), nullable=False)  # OWNED | IMPORTED

    # Tag-based classification (Module 2)
    predicted_tags = Column(JSONB, nullable=False, default=list)  # Immutable AI predictions
    final_tags = Column(JSONB, nullable=False, default=list)  # User-confirmed (used for search)
    is_confirmed = Column(Boolean, default=False)

    name = Column(String(200))
    description = Column(String)
    custom_tags = Column(ARRAY(String), default=list)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
