"""add outfit preview

Revision ID: 20260402_000007
Revises: 20260402_000006
Create Date: 2026-04-02 18:00:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260402_000007"
down_revision: Union[str, None] = "20260402_000006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "outfit_preview_tasks",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_image_path", sa.Text(), nullable=False),
        sa.Column("person_view_type", sa.String(length=20), nullable=False),
        sa.Column(
            "garment_categories",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "input_count",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("prompt_template_key", sa.String(length=100), nullable=False),
        sa.Column(
            "provider_name",
            sa.String(length=50),
            nullable=False,
            server_default=sa.text("'DashScope'"),
        ),
        sa.Column(
            "provider_model",
            sa.String(length=100),
            nullable=False,
            server_default=sa.text("'wan2.6-image'"),
        ),
        sa.Column("provider_job_id", sa.String(length=255), nullable=True),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'PENDING'"),
        ),
        sa.Column("preview_image_path", sa.Text(), nullable=True),
        sa.Column("error_code", sa.String(length=100), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint(
            "person_view_type IN ('FULL_BODY','UPPER_BODY')",
            name="ck_outfit_preview_person_view_type",
        ),
        sa.CheckConstraint(
            "status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_outfit_preview_status",
        ),
        sa.CheckConstraint("input_count >= 0", name="ck_outfit_preview_input_count"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index(
        "idx_outfit_preview_tasks_user_created",
        "outfit_preview_tasks",
        ["user_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "idx_outfit_preview_tasks_status_created",
        "outfit_preview_tasks",
        ["status", "created_at"],
        unique=False,
    )

    op.create_table(
        "outfit_preview_task_items",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("task_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("clothing_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("garment_category", sa.String(length=20), nullable=False),
        sa.Column(
            "sort_order",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("garment_image_path", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint(
            "garment_category IN ('TOP','BOTTOM','SHOES')",
            name="ck_outfit_preview_task_item_garment_category",
        ),
        sa.CheckConstraint("sort_order >= 0", name="ck_outfit_preview_task_item_sort"),
        sa.ForeignKeyConstraint(
            ["task_id"],
            ["outfit_preview_tasks.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["clothing_item_id"],
            ["clothing_items.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "task_id",
            "clothing_item_id",
            name="uq_outfit_preview_task_items_task_clothing_item",
        ),
        sa.UniqueConstraint(
            "task_id",
            "garment_category",
            name="uq_outfit_preview_task_items_task_category",
        ),
    )
    op.create_index(
        "idx_outfit_preview_task_items_task_order",
        "outfit_preview_task_items",
        ["task_id", "sort_order"],
        unique=False,
    )
    op.create_index(
        "idx_outfit_preview_task_items_task",
        "outfit_preview_task_items",
        ["task_id"],
        unique=False,
    )
    op.create_index(
        "idx_outfit_preview_task_items_clothing_item",
        "outfit_preview_task_items",
        ["clothing_item_id"],
        unique=False,
    )

    op.create_table(
        "outfits",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("preview_task_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("name", sa.String(length=120), nullable=True),
        sa.Column("preview_image_path", sa.Text(), nullable=False),
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
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["preview_task_id"],
            ["outfit_preview_tasks.id"],
            ondelete="SET NULL",
        ),
        sa.UniqueConstraint("preview_task_id", name="uq_outfits_preview_task_id"),
    )
    op.create_index(
        "idx_outfits_user_created",
        "outfits",
        ["user_id", "created_at"],
        unique=False,
    )

    op.create_table(
        "outfit_items",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("outfit_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("clothing_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.ForeignKeyConstraint(["outfit_id"], ["outfits.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["clothing_item_id"],
            ["clothing_items.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "outfit_id",
            "clothing_item_id",
            name="uq_outfit_items_outfit_clothing_item",
        ),
    )
    op.create_index(
        "idx_outfit_items_outfit",
        "outfit_items",
        ["outfit_id"],
        unique=False,
    )
    op.create_index(
        "idx_outfit_items_clothing_item",
        "outfit_items",
        ["clothing_item_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_outfit_items_clothing_item", table_name="outfit_items")
    op.drop_index("idx_outfit_items_outfit", table_name="outfit_items")
    op.drop_table("outfit_items")

    op.drop_index("idx_outfits_user_created", table_name="outfits")
    op.drop_table("outfits")

    op.drop_index(
        "idx_outfit_preview_task_items_clothing_item",
        table_name="outfit_preview_task_items",
    )
    op.drop_index(
        "idx_outfit_preview_task_items_task",
        table_name="outfit_preview_task_items",
    )
    op.drop_index(
        "idx_outfit_preview_task_items_task_order",
        table_name="outfit_preview_task_items",
    )
    op.drop_table("outfit_preview_task_items")

    op.drop_index(
        "idx_outfit_preview_tasks_status_created",
        table_name="outfit_preview_tasks",
    )
    op.drop_index(
        "idx_outfit_preview_tasks_user_created",
        table_name="outfit_preview_tasks",
    )
    op.drop_table("outfit_preview_tasks")
