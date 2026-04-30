"""align creator profile column naming and display name length

Revision ID: 20260420_000016
Revises: 20260420_000015
Create Date: 2026-04-20 10:20:00
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260420_000016"
down_revision: Union[str, None] = "20260420_000015"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {col["name"]: col for col in inspector.get_columns("creator_profiles")}

    if "avatar_storage_path" in cols and "avatar_url" not in cols:
        op.alter_column(
            "creator_profiles",
            "avatar_storage_path",
            new_column_name="avatar_url",
            existing_type=sa.Text(),
            existing_nullable=True,
        )

    display_col = cols.get("display_name")
    if display_col is not None:
        existing_type = display_col["type"]
        if getattr(existing_type, "length", None) != 100:
            op.alter_column(
                "creator_profiles",
                "display_name",
                existing_type=existing_type,
                type_=sa.String(length=100),
                existing_nullable=False,
            )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = {col["name"]: col for col in inspector.get_columns("creator_profiles")}

    if "avatar_url" in cols and "avatar_storage_path" not in cols:
        op.alter_column(
            "creator_profiles",
            "avatar_url",
            new_column_name="avatar_storage_path",
            existing_type=sa.Text(),
            existing_nullable=True,
        )

    display_col = cols.get("display_name")
    if display_col is not None:
        existing_type = display_col["type"]
        if getattr(existing_type, "length", None) != 120:
            op.alter_column(
                "creator_profiles",
                "display_name",
                existing_type=existing_type,
                type_=sa.String(length=120),
                existing_nullable=False,
            )
