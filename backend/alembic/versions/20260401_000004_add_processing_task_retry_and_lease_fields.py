"""add processing task retry and lease fields

Revision ID: 20260401_000004
Revises: 20260307_000003
Create Date: 2026-04-01
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "20260401_000004"
down_revision: Union[str, None] = "20260307_000003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "processing_tasks",
        sa.Column("attempt_no", sa.Integer(), server_default="1", nullable=False),
    )
    op.add_column(
        "processing_tasks",
        sa.Column("retry_of_task_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "processing_tasks",
        sa.Column("worker_id", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "processing_tasks",
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_processing_tasks_retry_of_task_id",
        "processing_tasks",
        "processing_tasks",
        ["retry_of_task_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_check_constraint(
        "ck_attempt_no",
        "processing_tasks",
        "attempt_no >= 1",
    )
    op.create_index(
        "uq_processing_tasks_active_item",
        "processing_tasks",
        ["clothing_item_id"],
        unique=True,
        postgresql_where=sa.text("status IN ('PENDING','PROCESSING')"),
    )
    op.alter_column("processing_tasks", "attempt_no", server_default=None)


def downgrade() -> None:
    op.drop_index("uq_processing_tasks_active_item", table_name="processing_tasks")
    op.drop_constraint("ck_attempt_no", "processing_tasks", type_="check")
    op.drop_constraint(
        "fk_processing_tasks_retry_of_task_id",
        "processing_tasks",
        type_="foreignkey",
    )
    op.drop_column("processing_tasks", "lease_expires_at")
    op.drop_column("processing_tasks", "worker_id")
    op.drop_column("processing_tasks", "retry_of_task_id")
    op.drop_column("processing_tasks", "attempt_no")
