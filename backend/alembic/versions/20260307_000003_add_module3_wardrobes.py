"""add module3 wardrobes and wardrobe_items

Revision ID: 20260307_000003
Revises: 20260307_000002
Create Date: 2026-03-07

Module 3: Wardrobe management. Deleting a wardrobe only removes wardrobe_items, not clothing_items.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260307_000003"
down_revision: Union[str, None] = "20260307_000002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "wardrobes",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("type", sa.String(20), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.CheckConstraint("type IN ('REGULAR', 'VIRTUAL')", name="ck_wardrobe_type"),
    )
    op.create_index("idx_wardrobes_user", "wardrobes", ["user_id"], unique=False)

    op.create_table(
        "wardrobe_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("wardrobe_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("clothing_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "added_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.Column("display_order", sa.Integer(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["wardrobe_id"], ["wardrobes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["clothing_item_id"], ["clothing_items.id"], ondelete="CASCADE"
        ),
        sa.UniqueConstraint("wardrobe_id", "clothing_item_id", name="uq_wardrobe_item"),
    )
    op.create_index(
        "idx_wardrobe_items_wardrobe", "wardrobe_items", ["wardrobe_id"], unique=False
    )
    op.create_index(
        "idx_wardrobe_items_clothing",
        "wardrobe_items",
        ["clothing_item_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_wardrobe_items_clothing", table_name="wardrobe_items")
    op.drop_index("idx_wardrobe_items_wardrobe", table_name="wardrobe_items")
    op.drop_table("wardrobe_items")
    op.drop_index("idx_wardrobes_user", table_name="wardrobes")
    op.drop_table("wardrobes")
