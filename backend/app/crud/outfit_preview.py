from datetime import datetime, timezone
from uuid import UUID, uuid4

from sqlalchemy.orm import Session

from app.models.outfit_preview import (
    Outfit,
    OutfitItem,
    OutfitPreviewTask,
    OutfitPreviewTaskItem,
)


def create_outfit_preview_task(
    db: Session,
    *,
    user_id: UUID,
    person_image_blob_hash: str,
    person_view_type: str,
    garment_categories: list[str],
    prompt_template_key: str,
    provider_name: str = "DashScope",
    provider_model: str = "wan2.6-image",
) -> OutfitPreviewTask:
    now = datetime.now(timezone.utc)
    task = OutfitPreviewTask(
        id=uuid4(),
        user_id=user_id,
        person_image_blob_hash=person_image_blob_hash,
        person_view_type=person_view_type,
        garment_categories=garment_categories,
        input_count=len(garment_categories),
        prompt_template_key=prompt_template_key,
        provider_name=provider_name,
        provider_model=provider_model,
        status="PENDING",
        created_at=now,
    )
    db.add(task)
    db.flush()
    return task


def replace_outfit_preview_task_items(
    db: Session,
    *,
    task: OutfitPreviewTask,
    items: list[dict],
) -> OutfitPreviewTask:
    task.items.clear()
    for item in items:
        task.items.append(
            OutfitPreviewTaskItem(
                id=uuid4(),
                task_id=task.id,
                clothing_item_id=item["clothing_item_id"],
                garment_category=item["garment_category"],
                sort_order=item["sort_order"],
                garment_image_blob_hash=item["garment_image_blob_hash"],
                created_at=item.get("created_at", datetime.now(timezone.utc)),
            )
        )
    db.flush()
    return task


def get_outfit_preview_task(
    db: Session,
    task_id: UUID,
) -> OutfitPreviewTask | None:
    return db.query(OutfitPreviewTask).filter(OutfitPreviewTask.id == task_id).first()


def get_owned_outfit_preview_task(
    db: Session,
    *,
    task_id: UUID,
    user_id: UUID,
    for_update: bool = False,
) -> OutfitPreviewTask | None:
    query = db.query(OutfitPreviewTask).filter(
        OutfitPreviewTask.id == task_id,
        OutfitPreviewTask.user_id == user_id,
    )
    if for_update:
        query = query.with_for_update()
    return query.first()


def list_owned_outfit_preview_tasks(
    db: Session,
    *,
    user_id: UUID,
    status: str | None = None,
    page: int = 1,
    limit: int = 20,
) -> tuple[list[OutfitPreviewTask], int]:
    query = db.query(OutfitPreviewTask).filter(OutfitPreviewTask.user_id == user_id)
    if status:
        query = query.filter(OutfitPreviewTask.status == status)
    total = query.count()
    items = (
        query.order_by(OutfitPreviewTask.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    return items, total


def mark_outfit_preview_processing(
    db: Session,
    *,
    task: OutfitPreviewTask,
    worker_id: str | None = None,
) -> OutfitPreviewTask | None:
    if task.status != "PENDING":
        return None
    now = datetime.now(timezone.utc)
    task.status = "PROCESSING"
    task.started_at = now
    task.completed_at = None
    task.error_code = None
    task.error_message = None
    db.commit()
    db.refresh(task)
    return task


def mark_outfit_preview_completed(
    db: Session,
    *,
    task: OutfitPreviewTask,
    preview_image_blob_hash: str,
    provider_job_id: str | None = None,
) -> OutfitPreviewTask:
    now = datetime.now(timezone.utc)
    task.status = "COMPLETED"
    task.preview_image_blob_hash = preview_image_blob_hash
    task.provider_job_id = provider_job_id
    task.error_code = None
    task.error_message = None
    task.completed_at = now
    db.commit()
    db.refresh(task)
    return task


def mark_outfit_preview_failed(
    db: Session,
    *,
    task: OutfitPreviewTask,
    error_code: str | None,
    error_message: str,
    provider_job_id: str | None = None,
) -> OutfitPreviewTask:
    now = datetime.now(timezone.utc)
    task.status = "FAILED"
    task.provider_job_id = provider_job_id
    task.error_code = error_code
    task.error_message = error_message
    task.completed_at = now
    db.commit()
    db.refresh(task)
    return task


def get_owned_outfit_by_preview_task(
    db: Session,
    *,
    preview_task_id: UUID,
    user_id: UUID,
) -> Outfit | None:
    return (
        db.query(Outfit)
        .filter(
            Outfit.preview_task_id == preview_task_id,
            Outfit.user_id == user_id,
        )
        .first()
    )


def create_outfit_from_preview_task(
    db: Session,
    *,
    task: OutfitPreviewTask,
    name: str | None = None,
) -> Outfit:
    existing = (
        db.query(Outfit)
        .filter(Outfit.preview_task_id == task.id, Outfit.user_id == task.user_id)
        .first()
    )
    if existing is not None:
        return existing

    outfit = Outfit(
        id=uuid4(),
        user_id=task.user_id,
        preview_task_id=task.id,
        name=name,
        preview_image_blob_hash=task.preview_image_blob_hash or "",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db.add(outfit)
    db.flush()

    for task_item in sorted(task.items, key=lambda item: item.sort_order):
        outfit_item = OutfitItem(
            id=uuid4(),
            outfit_id=outfit.id,
            clothing_item_id=task_item.clothing_item_id,
            created_at=datetime.now(timezone.utc),
        )
        outfit.items.append(outfit_item)
        db.add(outfit_item)

    db.commit()
    db.refresh(outfit)
    return outfit
