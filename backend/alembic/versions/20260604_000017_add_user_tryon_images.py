"""add user try-on images

Revision ID: 20260604_000017
Revises: 20260420_000016
Create Date: 2026-06-04 00:00:00
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260604_000017"
down_revision: Union[str, None] = "20260420_000016"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_tryon_images",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("blob_hash", sa.String(length=64), nullable=False),
        sa.Column("person_view_type", sa.String(length=20), nullable=False),
        sa.Column("is_default", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "person_view_type IN ('FULL_BODY','UPPER_BODY')",
            name="ck_user_tryon_image_person_view_type",
        ),
        sa.ForeignKeyConstraint(["blob_hash"], ["blobs.blob_hash"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_user_tryon_images_user_id"),
        "user_tryon_images",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "uq_user_tryon_images_one_default",
        "user_tryon_images",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("is_default IS TRUE"),
    )


def downgrade() -> None:
    op.drop_index("uq_user_tryon_images_one_default", table_name="user_tryon_images")
    op.drop_index(op.f("ix_user_tryon_images_user_id"), table_name="user_tryon_images")
    op.drop_table("user_tryon_images")
