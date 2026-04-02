import io
import logging
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.creator import (
    CreatorItem,
    CreatorItemImage,
    CreatorItemModel3D,
    CreatorProcessingTask,
)
from app.services import angle_renderer_service as renderer
from app.services import background_removal_service as bg
from app.services import model_3d_service as m3d
from app.services.ai_service import AIService
from app.services.creator_processing_task_service import claim_processing_task
from app.services.storage_service import StorageService, get_storage_service

logger = logging.getLogger(__name__)

DERIVED_IMAGE_TYPES = ("PROCESSED_FRONT", "PROCESSED_BACK", "ANGLE_VIEW")


async def run_creator_pipeline_task(task_id: UUID, worker_id: str | None = None) -> bool:
    db = SessionLocal()
    storage = get_storage_service()
    worker = worker_id or f"creator-{task_id}"

    try:
        task = claim_processing_task(db, task_id, worker_id=worker)
        if task is None:
            logger.info("Creator task %s already claimed or no longer pending", task_id)
            return False

        item = (
            db.query(CreatorItem)
            .filter(CreatorItem.id == task.creator_item_id)
            .first()
        )
        if item is None:
            raise RuntimeError(f"Creator item {task.creator_item_id} not found")

        item.processing_status = "PROCESSING"
        db.commit()
        front_bytes, back_bytes = await _load_original_images(db, storage, item.id)
        ai_service = AIService()

        await cleanup_creator_pipeline_artifacts(db, storage, item.id)
        _update(db, task, 5)

        front_proc = await bg.remove_background(front_bytes)
        proc_front_path = _item_path(item.creator_id, item.id, "processed_front.png")
        await storage.upload(io.BytesIO(front_proc), proc_front_path)
        _upsert_image(db, item.id, "PROCESSED_FRONT", proc_front_path)

        back_proc = None
        if back_bytes:
            back_proc = await bg.remove_background(back_bytes)
            proc_back_path = _item_path(item.creator_id, item.id, "processed_back.png")
            await storage.upload(io.BytesIO(back_proc), proc_back_path)
            _upsert_image(db, item.id, "PROCESSED_BACK", proc_back_path)
        _update(db, task, 25)

        predicted_tags = ai_service.classify_bytes(front_proc)
        item.predicted_tags = [_tag_to_dict(tag) for tag in predicted_tags]
        item.final_tags = list(item.predicted_tags)
        item.is_confirmed = False
        db.commit()

        _update(db, task, 30)
        mesh = await m3d.generate_3d_model(front_proc, back_proc)
        glb_bytes = m3d.export_mesh(mesh, "glb")
        model_path = _item_path(item.creator_id, item.id, "model.glb")
        await storage.upload(io.BytesIO(glb_bytes), model_path)
        _upsert_model(
            db,
            item.id,
            model_path=model_path,
            vertex_count=len(mesh.vertices),
            face_count=len(mesh.faces),
            file_size=len(glb_bytes),
        )
        _update(db, task, 70)

        angle_images = renderer.render_all_angles(mesh)
        for angle_deg, png_bytes in angle_images.items():
            angle_path = _item_path(item.creator_id, item.id, f"angle_{angle_deg:03d}.png")
            await storage.upload(io.BytesIO(png_bytes), angle_path)
            _upsert_image(db, item.id, "ANGLE_VIEW", angle_path, angle=angle_deg)
        _update(db, task, 95)

        item.processing_status = "COMPLETED"
        task.status = "COMPLETED"
        task.progress = 100
        task.completed_at = datetime.now(timezone.utc)
        task.lease_expires_at = None
        db.commit()
        return True
    except Exception as exc:
        db.rollback()
        task = db.query(CreatorProcessingTask).filter(CreatorProcessingTask.id == task_id).first()
        if task is not None:
            item = db.query(CreatorItem).filter(CreatorItem.id == task.creator_item_id).first()
            if item is not None:
                await cleanup_creator_pipeline_artifacts(db, storage, item.id)
                item.processing_status = "FAILED"
            task.status = "FAILED"
            task.error_message = str(exc)[:500]
            task.completed_at = datetime.now(timezone.utc)
            task.lease_expires_at = None
            db.commit()
        logger.exception("Creator pipeline failed for task %s", task_id)
        raise
    finally:
        db.close()


def _update(db: Session, task: CreatorProcessingTask, progress: int) -> None:
    task.progress = progress
    db.commit()


async def cleanup_creator_pipeline_artifacts(
    db: Session,
    storage: StorageService,
    creator_item_id: UUID,
    *,
    commit: bool = True,
) -> None:
    item = db.query(CreatorItem).filter(CreatorItem.id == creator_item_id).first()
    if item is None:
        return

    derived_images = (
        db.query(CreatorItemImage)
        .filter(
            CreatorItemImage.creator_item_id == creator_item_id,
            CreatorItemImage.image_type.in_(DERIVED_IMAGE_TYPES),
        )
        .all()
    )
    model = (
        db.query(CreatorItemModel3D)
        .filter(CreatorItemModel3D.creator_item_id == creator_item_id)
        .first()
    )

    paths = {img.storage_path for img in derived_images}
    if model is not None:
        paths.add(model.storage_path)
    paths.update(_derived_paths(item.creator_id, creator_item_id))

    db.query(CreatorItemImage).filter(
        CreatorItemImage.creator_item_id == creator_item_id,
        CreatorItemImage.image_type.in_(DERIVED_IMAGE_TYPES),
    ).delete(synchronize_session=False)
    db.query(CreatorItemModel3D).filter(
        CreatorItemModel3D.creator_item_id == creator_item_id
    ).delete(synchronize_session=False)
    if commit:
        db.commit()

    for path in paths:
        try:
            await storage.delete(path)
        except Exception:
            logger.warning(
                "Failed to cleanup creator storage path %s",
                path,
                exc_info=True,
            )


async def _load_original_images(
    db: Session,
    storage: StorageService,
    creator_item_id: UUID,
) -> tuple[bytes, bytes | None]:
    images = (
        db.query(CreatorItemImage)
        .filter(
            CreatorItemImage.creator_item_id == creator_item_id,
            CreatorItemImage.image_type.in_(["ORIGINAL_FRONT", "ORIGINAL_BACK"]),
        )
        .all()
    )
    front_bytes = None
    back_bytes = None
    for img in images:
        payload = await storage.download(img.storage_path)
        if img.image_type == "ORIGINAL_FRONT":
            front_bytes = payload
        else:
            back_bytes = payload

    if front_bytes is None:
        raise RuntimeError(f"Missing original front image for creator item {creator_item_id}")
    return front_bytes, back_bytes


def _upsert_image(
    db: Session,
    creator_item_id: UUID,
    image_type: str,
    path: str,
    angle: int | None = None,
) -> None:
    image = (
        db.query(CreatorItemImage)
        .filter(
            CreatorItemImage.creator_item_id == creator_item_id,
            CreatorItemImage.image_type == image_type,
            CreatorItemImage.angle == angle,
        )
        .first()
    )
    if image is None:
        image = CreatorItemImage(
            creator_item_id=creator_item_id,
            image_type=image_type,
            storage_path=path,
            angle=angle,
        )
        db.add(image)
    else:
        image.storage_path = path
    db.commit()


def _upsert_model(
    db: Session,
    creator_item_id: UUID,
    *,
    model_path: str,
    vertex_count: int,
    face_count: int,
    file_size: int,
) -> None:
    model = (
        db.query(CreatorItemModel3D)
        .filter(CreatorItemModel3D.creator_item_id == creator_item_id)
        .first()
    )
    if model is None:
        model = CreatorItemModel3D(creator_item_id=creator_item_id)
        db.add(model)
    model.model_format = "glb"
    model.storage_path = model_path
    model.vertex_count = vertex_count
    model.face_count = face_count
    model.file_size = file_size
    db.commit()


def _item_path(creator_id: UUID, creator_item_id: UUID, filename: str) -> str:
    return f"creators/{creator_id}/{creator_item_id}/{filename}"


def _derived_paths(creator_id: UUID, creator_item_id: UUID) -> set[str]:
    paths = {
        _item_path(creator_id, creator_item_id, "processed_front.png"),
        _item_path(creator_id, creator_item_id, "processed_back.png"),
        _item_path(creator_id, creator_item_id, "model.glb"),
    }
    paths.update(
        _item_path(creator_id, creator_item_id, f"angle_{angle:03d}.png")
        for angle in (0, 45, 90, 135, 180, 225, 270, 315)
    )
    return paths


def _tag_to_dict(tag) -> dict[str, str]:
    if isinstance(tag, dict):
        return tag
    return {"key": tag.key, "value": tag.value}
