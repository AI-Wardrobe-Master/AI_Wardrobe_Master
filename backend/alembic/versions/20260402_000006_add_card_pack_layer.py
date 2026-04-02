"""add card pack layer

Revision ID: 20260402_000006
Revises: 20260402_000005
Create Date: 2026-04-02 16:00:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260402_000006"
down_revision: Union[str, None] = "20260402_000005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "card_packs",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("creator_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "pack_type",
            sa.String(length=40),
            nullable=False,
            server_default=sa.text("'CLOTHING_COLLECTION'"),
        ),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'DRAFT'"),
        ),
        sa.Column("cover_image_storage_path", sa.Text(), nullable=True),
        sa.Column("share_id", sa.String(length=64), nullable=True),
        sa.Column(
            "import_count",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint(
            "pack_type IN ('CLOTHING_COLLECTION')",
            name="ck_card_pack_type",
        ),
        sa.CheckConstraint(
            "status IN ('DRAFT','PUBLISHED','ARCHIVED')",
            name="ck_card_pack_status",
        ),
        sa.ForeignKeyConstraint(["creator_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("share_id", name="uq_card_packs_share_id"),
    )
    op.create_index(
        "idx_card_pack_creator_status",
        "card_packs",
        ["creator_id", "status"],
        unique=False,
    )
    op.create_index(
        "idx_card_pack_creator_created",
        "card_packs",
        ["creator_id", "created_at"],
        unique=False,
    )

    op.create_table(
        "card_pack_items",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("card_pack_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("creator_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "sort_order",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint("sort_order >= 0", name="ck_card_pack_item_sort_order"),
        sa.ForeignKeyConstraint(
            ["card_pack_id"],
            ["card_packs.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["creator_item_id"],
            ["creator_items.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "card_pack_id",
            "creator_item_id",
            name="uq_card_pack_items_pack_creator_item",
        ),
        sa.UniqueConstraint(
            "card_pack_id",
            "sort_order",
            name="uq_card_pack_items_pack_sort_order",
        ),
    )
    op.create_index(
        "idx_card_pack_items_pack",
        "card_pack_items",
        ["card_pack_id"],
        unique=False,
    )
    op.create_index(
        "idx_card_pack_items_creator_item",
        "card_pack_items",
        ["creator_item_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_card_pack_items_creator_item", table_name="card_pack_items")
    op.drop_index("idx_card_pack_items_pack", table_name="card_pack_items")
    op.drop_table("card_pack_items")

    op.drop_index("idx_card_pack_creator_created", table_name="card_packs")
    op.drop_index("idx_card_pack_creator_status", table_name="card_packs")
    op.drop_table("card_packs")
