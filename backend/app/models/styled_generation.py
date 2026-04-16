import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base


class StyledGeneration(Base):
    __tablename__ = "styled_generations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    source_clothing_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("clothing_items.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    selfie_original_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
    selfie_processed_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=True)

    scene_prompt = Column(Text, nullable=False)
    negative_prompt = Column(Text, nullable=True)
    dreamo_version = Column(String(10), nullable=False, default="v1.1")

    status = Column(String(20), nullable=False, default="PENDING")
    progress = Column(Integer, nullable=False, default=0)
    result_image_blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=True)
    failure_reason = Column(Text, nullable=True)

    guidance_scale = Column(Float, nullable=False, default=4.5)
    seed = Column(Integer, nullable=False, default=-1)
    width = Column(Integer, nullable=False, default=1024)
    height = Column(Integer, nullable=False, default=1024)

    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('PENDING','PROCESSING','SUCCEEDED','FAILED')",
            name="ck_styled_gen_status",
        ),
        CheckConstraint(
            "progress BETWEEN 0 AND 100",
            name="ck_styled_gen_progress",
        ),
        Index("idx_styled_gen_user_created", "user_id", "created_at"),
    )

    clothing_item = relationship(
        "ClothingItem", foreign_keys=[source_clothing_item_id]
    )
