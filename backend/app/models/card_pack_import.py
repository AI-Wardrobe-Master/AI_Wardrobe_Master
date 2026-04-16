import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class CardPackImport(Base):
    __tablename__ = "card_pack_imports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    card_pack_id = Column(
        UUID(as_uuid=True),
        ForeignKey("card_packs.id", ondelete="RESTRICT"),
        nullable=False,
    )
    imported_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    __table_args__ = (
        UniqueConstraint("user_id", "card_pack_id", name="uq_card_pack_imports_user_pack"),
        Index("idx_card_pack_imports_pack", "card_pack_id"),
    )
