from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.creator import CreatorProcessingTask


def get_latest_task(db: Session, creator_item_id: UUID) -> CreatorProcessingTask | None:
    return (
        db.query(CreatorProcessingTask)
        .filter(CreatorProcessingTask.creator_item_id == creator_item_id)
        .order_by(CreatorProcessingTask.created_at.desc())
        .first()
    )


def create_processing_task(
    db: Session,
    creator_item_id: UUID,
    *,
    attempt_no: int,
    retry_of_task_id: UUID | None = None,
) -> CreatorProcessingTask:
    task = CreatorProcessingTask(
        id=uuid4(),
        creator_item_id=creator_item_id,
        task_type="FULL_PIPELINE",
        attempt_no=attempt_no,
        retry_of_task_id=retry_of_task_id,
        status="PENDING",
        progress=0,
    )
    db.add(task)
    db.flush()
    return task


def claim_processing_task(
    db: Session,
    task_id: UUID,
    *,
    worker_id: str,
) -> CreatorProcessingTask | None:
    now = datetime.now(timezone.utc)
    lease_expires_at = now + timedelta(seconds=settings.PROCESSING_TASK_LEASE_SECONDS)

    stmt = (
        update(CreatorProcessingTask)
        .where(
            CreatorProcessingTask.id == task_id,
            CreatorProcessingTask.status == "PENDING",
        )
        .values(
            status="PROCESSING",
            started_at=now,
            completed_at=None,
            worker_id=worker_id,
            lease_expires_at=lease_expires_at,
            error_message=None,
        )
        .returning(CreatorProcessingTask.id)
    )
    claimed_id = db.execute(stmt).scalar_one_or_none()
    if claimed_id is None:
        db.rollback()
        return None

    db.commit()
    return db.execute(
        select(CreatorProcessingTask).where(CreatorProcessingTask.id == claimed_id)
    ).scalar_one()
