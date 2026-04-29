from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from sqlalchemy import and_, select, update
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.clothing_item import ProcessingTask


ACTIVE_TASK_STATUSES = ("PENDING", "PROCESSING")


def get_latest_task(db: Session, clothing_item_id: UUID) -> ProcessingTask | None:
    return (
        db.query(ProcessingTask)
        .filter(ProcessingTask.clothing_item_id == clothing_item_id)
        .order_by(ProcessingTask.created_at.desc())
        .first()
    )


def create_processing_task(
    db: Session,
    clothing_item_id: UUID,
    *,
    attempt_no: int,
    retry_of_task_id: UUID | None = None,
) -> ProcessingTask:
    task = ProcessingTask(
        id=uuid4(),
        clothing_item_id=clothing_item_id,
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
) -> ProcessingTask | None:
    now = datetime.now(timezone.utc)
    lease_expires_at = now + timedelta(seconds=settings.PROCESSING_TASK_LEASE_SECONDS)

    stmt = (
        update(ProcessingTask)
        .where(
            ProcessingTask.id == task_id,
            ProcessingTask.status == "PENDING",
        )
        .values(
            status="PROCESSING",
            started_at=now,
            completed_at=None,
            worker_id=worker_id,
            lease_expires_at=lease_expires_at,
            error_message=None,
        )
        .returning(ProcessingTask.id)
    )
    claimed_id = db.execute(stmt).scalar_one_or_none()
    if claimed_id is None:
        db.rollback()
        return None

    db.commit()
    return db.execute(
        select(ProcessingTask).where(ProcessingTask.id == claimed_id)
    ).scalar_one()


def fail_expired_tasks(db: Session) -> int:
    now = datetime.now(timezone.utc)
    stmt = (
        update(ProcessingTask)
        .where(
            and_(
                ProcessingTask.status == "PROCESSING",
                ProcessingTask.lease_expires_at.is_not(None),
                ProcessingTask.lease_expires_at < now,
            )
        )
        .values(
            status="FAILED",
            error_message="Worker lease expired",
            completed_at=now,
            lease_expires_at=None,
        )
    )
    result = db.execute(stmt)
    db.commit()
    return result.rowcount or 0
