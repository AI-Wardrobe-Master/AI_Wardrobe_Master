"""init module2 schema

Revision ID: 20260307_000001
Revises:
Create Date: 2026-03-07 08:10:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "20260307_000001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute('CREATE EXTENSION IF NOT EXISTS pgcrypto')

    op.create_table(
        "users",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("username", sa.String(length=50), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("hashed_password", sa.String(length=255), nullable=False),
        sa.Column("user_type", sa.String(length=20), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("TRUE")),
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
        sa.CheckConstraint("user_type IN ('CONSUMER', 'CREATOR')", name="ck_user_type"),
        sa.UniqueConstraint("username", name="uq_users_username"),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )

    op.create_table(
        "clothing_items",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source", sa.String(length=20), nullable=False, server_default=sa.text("'OWNED'")),
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
        sa.Column("is_confirmed", sa.Boolean(), nullable=False, server_default=sa.text("FALSE")),
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
        sa.CheckConstraint("source IN ('OWNED', 'IMPORTED')", name="ck_source"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("idx_clothing_user", "clothing_items", ["user_id"], unique=False)
    op.create_index("idx_clothing_source", "clothing_items", ["source"], unique=False)
    op.create_index("idx_clothing_user_source", "clothing_items", ["user_id", "source"], unique=False)
    op.create_index("idx_clothing_user_created", "clothing_items", ["user_id", "created_at"], unique=False)
    op.create_index(
        "idx_clothing_final_tags",
        "clothing_items",
        ["final_tags"],
        unique=False,
        postgresql_using="gin",
    )
    op.create_index(
        "idx_clothing_custom_tags",
        "clothing_items",
        ["custom_tags"],
        unique=False,
        postgresql_using="gin",
    )

    op.create_table(
        "images",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("clothing_item_id", postgresql.UUID(as_uuid=True), nullable=False),
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
            name="ck_image_type",
        ),
        sa.CheckConstraint(
            "angle IS NULL OR angle IN (0,45,90,135,180,225,270,315)",
            name="ck_angle",
        ),
        sa.ForeignKeyConstraint(["clothing_item_id"], ["clothing_items.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "clothing_item_id",
            "image_type",
            "angle",
            name="uq_images_item_type_angle",
        ),
    )
    op.create_index("idx_images_clothing", "images", ["clothing_item_id"], unique=False)

    op.create_table(
        "models_3d",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("clothing_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("model_format", sa.String(length=10), nullable=False, server_default=sa.text("'glb'")),
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
        sa.CheckConstraint("model_format IN ('glb')", name="ck_model_format"),
        sa.ForeignKeyConstraint(["clothing_item_id"], ["clothing_items.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("clothing_item_id", name="uq_models_3d_clothing_item_id"),
    )

    op.create_table(
        "processing_tasks",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("clothing_item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("task_type", sa.String(length=30), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default=sa.text("'PENDING'")),
        sa.Column("progress", sa.Integer(), nullable=False, server_default=sa.text("0")),
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
            "task_type IN ('CLASSIFICATION','BACKGROUND_REMOVAL','3D_GENERATION',"
            "'ANGLE_RENDERING','FULL_PIPELINE')",
            name="ck_task_type",
        ),
        sa.CheckConstraint(
            "status IN ('PENDING','PROCESSING','COMPLETED','FAILED')",
            name="ck_task_status",
        ),
        sa.CheckConstraint("progress BETWEEN 0 AND 100", name="ck_progress"),
        sa.ForeignKeyConstraint(["clothing_item_id"], ["clothing_items.id"], ondelete="CASCADE"),
    )
    op.create_index(
        "idx_processing_tasks_item_created",
        "processing_tasks",
        ["clothing_item_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_processing_tasks_item_created", table_name="processing_tasks")
    op.drop_table("processing_tasks")
    op.drop_table("models_3d")
    op.drop_index("idx_images_clothing", table_name="images")
    op.drop_table("images")
    op.drop_index("idx_clothing_custom_tags", table_name="clothing_items", postgresql_using="gin")
    op.drop_index("idx_clothing_final_tags", table_name="clothing_items", postgresql_using="gin")
    op.drop_index("idx_clothing_user_created", table_name="clothing_items")
    op.drop_index("idx_clothing_user_source", table_name="clothing_items")
    op.drop_index("idx_clothing_source", table_name="clothing_items")
    op.drop_index("idx_clothing_user", table_name="clothing_items")
    op.drop_table("clothing_items")
    op.drop_table("users")
