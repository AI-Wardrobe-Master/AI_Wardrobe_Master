"""add creator foundation

Revision ID: 20260402_000005
Revises: 20260401_000004
Create Date: 2026-04-02 11:30:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "20260402_000005"
down_revision: Union[str, None] = "20260401_000004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "creator_profiles",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'ACTIVE'"),
        ),
        sa.Column("display_name", sa.String(length=120), nullable=False),
        sa.Column("brand_name", sa.String(length=120), nullable=True),
        sa.Column("bio", sa.Text(), nullable=True),
        sa.Column("avatar_storage_path", sa.Text(), nullable=True),
        sa.Column("website_url", sa.Text(), nullable=True),
        sa.Column(
            "social_links",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "is_verified",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("FALSE"),
        ),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
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
            "status IN ('PENDING','ACTIVE','SUSPENDED')",
            name="ck_creator_profile_status",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id"),
    )

    op.create_table(
        "creator_items",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("creator_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "catalog_visibility",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'PACK_ONLY'"),
        ),
        sa.Column(
            "processing_status",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'PENDING'"),
        ),
        sa.Column(
            "predicted_tags",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "final_tags",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "is_confirmed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("FALSE"),
        ),
        sa.Column("name", sa.String(length=200), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "custom_tags",
            postgresql.ARRAY(sa.String()),
            nullable=True,
            server_default=sa.text("'{}'"),
        ),
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
            "catalog_visibility IN ('PRIVATE','PACK_ONLY','PUBLIC')",
            name="ck_creator_item_visibility",
        ),
        sa.CheckConstraint(
            "processing_status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_creator_item_processing_status",
        ),
        sa.ForeignKeyConstraint(["creator_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index(
        "idx_creator_items_creator_id",
        "creator_items",
        ["creator_id"],
        unique=False,
    )
    op.create_index(
        "idx_creator_items_creator_created",
        "creator_items",
        ["creator_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "idx_creator_items_creator_visibility",
        "creator_items",
        ["creator_id", "catalog_visibility"],
        unique=False,
    )
    op.create_index(
        "idx_creator_items_final_tags",
        "creator_items",
        ["final_tags"],
        unique=False,
        postgresql_using="gin",
    )
    op.create_index(
        "idx_creator_items_custom_tags",
        "creator_items",
        ["custom_tags"],
        unique=False,
        postgresql_using="gin",
    )

    op.create_table(
        "creator_item_images",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("creator_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("image_type", sa.String(length=20), nullable=False),
        sa.Column("storage_path", sa.Text(), nullable=False),
        sa.Column("angle", sa.Integer(), nullable=True),
        sa.Column("file_size", sa.BigInteger(), nullable=True),
        sa.Column("mime_type", sa.String(length=50), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint(
            "image_type IN ('ORIGINAL_FRONT','ORIGINAL_BACK','PROCESSED_FRONT',"
            "'PROCESSED_BACK','ANGLE_VIEW')",
            name="ck_creator_item_image_type",
        ),
        sa.CheckConstraint(
            "angle IS NULL OR angle IN (0,45,90,135,180,225,270,315)",
            name="ck_creator_item_angle",
        ),
        sa.ForeignKeyConstraint(
            ["creator_item_id"],
            ["creator_items.id"],
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        "idx_creator_item_images_item_id",
        "creator_item_images",
        ["creator_item_id"],
        unique=False,
    )
    op.create_index(
        "uq_creator_item_images_null_angle",
        "creator_item_images",
        ["creator_item_id", "image_type"],
        unique=True,
        postgresql_where=sa.text("angle IS NULL"),
    )
    op.create_index(
        "uq_creator_item_images_angle_not_null",
        "creator_item_images",
        ["creator_item_id", "image_type", "angle"],
        unique=True,
        postgresql_where=sa.text("angle IS NOT NULL"),
    )

    op.create_table(
        "creator_models_3d",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("creator_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "model_format",
            sa.String(length=10),
            nullable=False,
            server_default=sa.text("'glb'"),
        ),
        sa.Column("storage_path", sa.Text(), nullable=False),
        sa.Column("vertex_count", sa.Integer(), nullable=True),
        sa.Column("face_count", sa.Integer(), nullable=True),
        sa.Column("file_size", sa.BigInteger(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint("model_format IN ('glb')", name="ck_creator_model_format"),
        sa.ForeignKeyConstraint(
            ["creator_item_id"],
            ["creator_items.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("creator_item_id", name="uq_creator_models_3d_item_id"),
    )

    op.create_table(
        "creator_processing_tasks",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("creator_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("task_type", sa.String(length=30), nullable=False),
        sa.Column(
            "attempt_no",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("1"),
        ),
        sa.Column("retry_of_task_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'PENDING'"),
        ),
        sa.Column(
            "progress",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("worker_id", sa.String(length=255), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint(
            "task_type IN ('CLASSIFICATION','BACKGROUND_REMOVAL','3D_GENERATION',"
            "'ANGLE_RENDERING','FULL_PIPELINE')",
            name="ck_creator_task_type",
        ),
        sa.CheckConstraint("attempt_no >= 1", name="ck_creator_attempt_no"),
        sa.CheckConstraint(
            "status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_creator_task_status",
        ),
        sa.CheckConstraint("progress BETWEEN 0 AND 100", name="ck_creator_progress"),
        sa.ForeignKeyConstraint(
            ["creator_item_id"],
            ["creator_items.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["retry_of_task_id"],
            ["creator_processing_tasks.id"],
            ondelete="SET NULL",
        ),
    )
    op.create_index(
        "idx_creator_processing_tasks_item_created",
        "creator_processing_tasks",
        ["creator_item_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "uq_creator_processing_tasks_active_item",
        "creator_processing_tasks",
        ["creator_item_id"],
        unique=True,
        postgresql_where=sa.text("status IN ('PENDING','PROCESSING')"),
    )


def downgrade() -> None:
    op.drop_index(
        "uq_creator_processing_tasks_active_item",
        table_name="creator_processing_tasks",
    )
    op.drop_index(
        "idx_creator_processing_tasks_item_created",
        table_name="creator_processing_tasks",
    )
    op.drop_table("creator_processing_tasks")
    op.drop_table("creator_models_3d")
    op.drop_index(
        "uq_creator_item_images_angle_not_null",
        table_name="creator_item_images",
    )
    op.drop_index(
        "uq_creator_item_images_null_angle",
        table_name="creator_item_images",
    )
    op.drop_index("idx_creator_item_images_item_id", table_name="creator_item_images")
    op.drop_table("creator_item_images")
    op.drop_index(
        "idx_creator_items_custom_tags",
        table_name="creator_items",
        postgresql_using="gin",
    )
    op.drop_index(
        "idx_creator_items_final_tags",
        table_name="creator_items",
        postgresql_using="gin",
    )
    op.drop_index("idx_creator_items_creator_visibility", table_name="creator_items")
    op.drop_index("idx_creator_items_creator_created", table_name="creator_items")
    op.drop_index("idx_creator_items_creator_id", table_name="creator_items")
    op.drop_table("creator_items")
    op.drop_table("creator_profiles")
