from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Column,
    DateTime,
    Index,
    Integer,
    String,
    Text,
)

from app.db.base import Base


class Blob(Base):
    __tablename__ = "blobs"

    blob_hash = Column(String(64), primary_key=True)
    byte_size = Column(BigInteger, nullable=False)
    mime_type = Column(String(100), nullable=False)
    ref_count = Column(Integer, nullable=False, default=0)
    first_seen_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    last_referenced_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    pending_delete_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint("ref_count >= 0", name="ck_blob_ref_count"),
        Index(
            "idx_blobs_pending_delete",
            "pending_delete_at",
            postgresql_where=Column("pending_delete_at").isnot(None),
        ),
    )
