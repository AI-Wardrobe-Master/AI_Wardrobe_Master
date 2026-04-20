"""add clothing metadata fields

Revision ID: 20260418_000012
Revises: 20260417_000011
Create Date: 2026-04-18
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260418_000012"
down_revision: Union[str, None] = "20260417_000011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("clothing_items", sa.Column("category", sa.String(length=100), nullable=True))
    op.add_column("clothing_items", sa.Column("material", sa.String(length=100), nullable=True))
    op.add_column("clothing_items", sa.Column("style", sa.String(length=100), nullable=True))
    op.add_column(
        "clothing_items",
        sa.Column("preview_svg_state", sa.String(length=20), server_default="PLACEHOLDER", nullable=False),
    )
    op.add_column(
        "clothing_items",
        sa.Column("preview_svg_available", sa.Boolean(), server_default=sa.text("true"), nullable=False),
    )
    op.add_column(
        "clothing_items",
        sa.Column("sync_status", sa.String(length=20), server_default="SYNCED", nullable=False),
    )

    op.create_check_constraint(
        "ck_clothing_preview_svg_state",
        "clothing_items",
        "preview_svg_state IN ('PLACEHOLDER','GENERATED','FAILED')",
    )
    op.create_check_constraint(
        "ck_clothing_sync_status",
        "clothing_items",
        "sync_status IN ('SYNCED','LOCAL_ONLY','PENDING_SYNC')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_clothing_sync_status", "clothing_items", type_="check")
    op.drop_constraint("ck_clothing_preview_svg_state", "clothing_items", type_="check")
    op.drop_column("clothing_items", "sync_status")
    op.drop_column("clothing_items", "preview_svg_available")
    op.drop_column("clothing_items", "preview_svg_state")
    op.drop_column("clothing_items", "style")
    op.drop_column("clothing_items", "material")
    op.drop_column("clothing_items", "category")
