"""Fix preview SVG availability defaults.

Revision ID: 20260418_000013
Revises: 20260418_000012
Create Date: 2026-04-18 14:05:00
"""

from alembic import op
import sqlalchemy as sa


revision = "20260418_000013"
down_revision = "20260418_000012"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "clothing_items",
        "preview_svg_available",
        existing_type=sa.Boolean(),
        server_default=sa.false(),
        existing_nullable=False,
    )

    op.execute(
        """
        UPDATE clothing_items ci
        SET preview_svg_available = FALSE
        WHERE NOT EXISTS (
            SELECT 1
            FROM models_3d m
            WHERE m.clothing_item_id = ci.id
        )
        AND NOT EXISTS (
            SELECT 1
            FROM images i
            WHERE i.clothing_item_id = ci.id
              AND i.image_type = 'ANGLE_VIEW'
        )
        """
    )


def downgrade() -> None:
    op.alter_column(
        "clothing_items",
        "preview_svg_available",
        existing_type=sa.Boolean(),
        server_default=sa.true(),
        existing_nullable=False,
    )
