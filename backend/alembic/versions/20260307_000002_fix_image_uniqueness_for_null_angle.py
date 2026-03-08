"""fix image uniqueness for null angle

Revision ID: 20260307_000002
Revises: 20260307_000001
Create Date: 2026-03-07 09:35:00
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20260307_000002"
down_revision: Union[str, None] = "20260307_000001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint("uq_images_item_type_angle", "images", type_="unique")
    op.create_index(
        "uq_images_item_type_null_angle",
        "images",
        ["clothing_item_id", "image_type"],
        unique=True,
        postgresql_where=sa.text("angle IS NULL"),
    )
    op.create_index(
        "uq_images_item_type_angle_not_null",
        "images",
        ["clothing_item_id", "image_type", "angle"],
        unique=True,
        postgresql_where=sa.text("angle IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_images_item_type_angle_not_null", table_name="images")
    op.drop_index("uq_images_item_type_null_angle", table_name="images")
    op.create_unique_constraint(
        "uq_images_item_type_angle",
        "images",
        ["clothing_item_id", "image_type", "angle"],
    )
