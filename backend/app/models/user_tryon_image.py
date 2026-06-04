import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    String,
    text,
)
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class UserTryOnImage(Base):
    __tablename__ = "user_tryon_images"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    blob_hash = Column(String(64), ForeignKey("blobs.blob_hash"), nullable=False)
    person_view_type = Column(String(20), nullable=False, default="FULL_BODY")
    is_default = Column(Boolean, nullable=False, default=True)
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
            "person_view_type IN ('FULL_BODY','UPPER_BODY')",
            name="ck_user_tryon_image_person_view_type",
        ),
        Index(
            "uq_user_tryon_images_one_default",
            "user_id",
            unique=True,
            postgresql_where=text("is_default IS TRUE"),
        ),
    )
