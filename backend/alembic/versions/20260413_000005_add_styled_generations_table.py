"""add styled_generations table

Revision ID: 20260413_000005
Revises: 20260401_000004
Create Date: 2026-04-13
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260413_000005"
down_revision: Union[str, None] = "20260401_000004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "styled_generations",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "source_clothing_item_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("clothing_items.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("selfie_original_path", sa.Text(), nullable=False),
        sa.Column("selfie_processed_path", sa.Text(), nullable=True),
        sa.Column("scene_prompt", sa.Text(), nullable=False),
        sa.Column("negative_prompt", sa.Text(), nullable=True),
        sa.Column(
            "dreamo_version",
            sa.String(10),
            nullable=False,
            server_default="v1.1",
        ),
        sa.Column(
            "status",
            sa.String(20),
            nullable=False,
            server_default="PENDING",
        ),
        sa.Column(
            "progress", sa.Integer(), nullable=False, server_default="0"
        ),
        sa.Column("result_image_path", sa.Text(), nullable=True),
        sa.Column("failure_reason", sa.Text(), nullable=True),
        sa.Column(
            "guidance_scale",
            sa.Float(),
            nullable=False,
            server_default="4.5",
        ),
        sa.Column(
            "seed", sa.Integer(), nullable=False, server_default="-1"
        ),
        sa.Column(
            "width", sa.Integer(), nullable=False, server_default="1024"
        ),
        sa.Column(
            "height", sa.Integer(), nullable=False, server_default="1024"
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
    )

    op.create_index(
        "idx_styled_gen_user_id", "styled_generations", ["user_id"]
    )
    op.create_index(
        "idx_styled_gen_clothing",
        "styled_generations",
        ["source_clothing_item_id"],
    )
    op.create_index(
        "idx_styled_gen_user_created",
        "styled_generations",
        ["user_id", "created_at"],
    )

    op.create_check_constraint(
        "ck_styled_gen_status",
        "styled_generations",
        "status IN ('PENDING','PROCESSING','SUCCEEDED','FAILED')",
    )
    op.create_check_constraint(
        "ck_styled_gen_progress",
        "styled_generations",
        "progress BETWEEN 0 AND 100",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_styled_gen_progress", "styled_generations", type_="check"
    )
    op.drop_constraint(
        "ck_styled_gen_status", "styled_generations", type_="check"
    )
    op.drop_index("idx_styled_gen_user_created", "styled_generations")
    op.drop_index("idx_styled_gen_clothing", "styled_generations")
    op.drop_index("idx_styled_gen_user_id", "styled_generations")
    op.drop_table("styled_generations")
