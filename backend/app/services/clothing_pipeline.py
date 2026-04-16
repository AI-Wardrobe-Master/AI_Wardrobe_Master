"""
Full clothing digitalization pipeline:
  originals already stored → background removal → 3D generation → angle rendering
"""
import io
import logging
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.clothing_item import ClothingItem, Image, Model3D, ProcessingTask
from app.services import background_removal_service as bg
from app.services import model_3d_service as m3d
from app.services import angle_renderer_service as renderer
from app.core.config import settings
from app.services.blob_service import get_blob_service
from app.services.blob_storage import get_blob_storage
from app.services.processing_task_service import claim_processing_task

logger = logging.getLogger(__name__)

DERIVED_IMAGE_TYPES = ("PROCESSED_FRONT", "PROCESSED_BACK", "ANGLE_VIEW")


async def run_pipeline_task(task_id: UUID, worker_id: str | None = None) -> bool:
    db = SessionLocal()
    blob_service = get_blob_service()
    blob_storage = get_blob_storage()
    worker = worker_id or f"pid-{task_id}"

    try:
        task = claim_processing_task(db, task_id, worker_id=worker)
        if task is None:
            logger.info("Task %s already claimed or no longer pending", task_id)
            return False

        item = (
            db.query(ClothingItem)
            .filter(ClothingItem.id == task.clothing_item_id)
            .first()
        )
        if item is None:
            raise RuntimeError(f"Clothing item {task.clothing_item_id} not found")

        front_bytes, back_bytes = await _load_original_images(db, blob_storage, item.id)

        await cleanup_pipeline_artifacts(db, item.id)
        _update(db, task, 5)

        front_proc = await bg.remove_background(front_bytes)
        proc_blob = await blob_service.ingest_upload(
            db, io.BytesIO(front_proc),
            claimed_mime_type="image/png",
            max_size=settings.MAX_UPLOAD_SIZE_BYTES * 2,
        )
        _upsert_image(db, item.id, "PROCESSED_FRONT", proc_blob.blob_hash)

        back_proc = None
        if back_bytes:
            back_proc = await bg.remove_background(back_bytes)
            back_blob = await blob_service.ingest_upload(
                db, io.BytesIO(back_proc),
                claimed_mime_type="image/png",
                max_size=settings.MAX_UPLOAD_SIZE_BYTES * 2,
            )
            _upsert_image(db, item.id, "PROCESSED_BACK", back_blob.blob_hash)
        _update(db, task, 25)

        _update(db, task, 30)
        mesh = await m3d.generate_3d_model(front_proc, back_proc)
        glb_bytes = m3d.export_mesh(mesh, "glb")
        model_blob = await blob_service.ingest_upload(
            db, io.BytesIO(glb_bytes),
            claimed_mime_type="model/gltf-binary",
            max_size=settings.MAX_UPLOAD_SIZE_BYTES * 5,
        )
        _upsert_model(
            db,
            item.id,
            blob_hash=model_blob.blob_hash,
            vertex_count=len(mesh.vertices),
            face_count=len(mesh.faces),
        )
        _update(db, task, 70)

        angle_images = renderer.render_all_angles(mesh)
        for angle_deg, png_bytes in angle_images.items():
            angle_blob = await blob_service.ingest_upload(
                db, io.BytesIO(png_bytes),
                claimed_mime_type="image/png",
                max_size=settings.MAX_UPLOAD_SIZE_BYTES * 2,
            )
            _upsert_image(db, item.id, "ANGLE_VIEW", angle_blob.blob_hash, angle=angle_deg)
        _update(db, task, 95)

        task.status = "COMPLETED"
        task.progress = 100
        task.completed_at = datetime.now(timezone.utc)
        task.lease_expires_at = None
        db.commit()
        logger.info("Pipeline complete for item %s", item.id)
        return True
    except Exception as exc:
        db.rollback()
        task = db.query(ProcessingTask).filter(ProcessingTask.id == task_id).first()
        if task is not None:
            item = (
                db.query(ClothingItem)
                .filter(ClothingItem.id == task.clothing_item_id)
                .first()
            )
            if item is not None:
                await cleanup_pipeline_artifacts(db, item.id)
            task.status = "FAILED"
            task.error_message = str(exc)[:500]
            task.completed_at = datetime.now(timezone.utc)
            task.lease_expires_at = None
            db.commit()
        logger.exception("Pipeline failed for task %s", task_id)
        raise
    finally:
        db.close()


def _update(db: Session, task: ProcessingTask, progress: int):
    task.progress = progress
    db.commit()


async def cleanup_pipeline_artifacts(
    db: Session,
    clothing_id: UUID,
    *,
    commit: bool = True,
) -> None:
    blob_service = get_blob_service()

    derived_images = (
        db.query(Image)
        .filter(
            Image.clothing_item_id == clothing_id,
            Image.image_type.in_(DERIVED_IMAGE_TYPES),
        )
        .all()
    )
    for img in derived_images:
        blob_service.release(db, img.blob_hash)
        db.delete(img)

    model = db.query(Model3D).filter(Model3D.clothing_item_id == clothing_id).first()
    if model:
        blob_service.release(db, model.blob_hash)
        db.delete(model)

    if commit:
        db.commit()


async def _load_original_images(
    db: Session,
    blob_storage,
    clothing_id: UUID,
) -> tuple[bytes, bytes | None]:
    images = (
        db.query(Image)
        .filter(
            Image.clothing_item_id == clothing_id,
            Image.image_type.in_(["ORIGINAL_FRONT", "ORIGINAL_BACK"]),
        )
        .all()
    )
    front_bytes = None
    back_bytes = None
    for img in images:
        payload = await blob_storage.get_bytes(img.blob_hash)
        if img.image_type == "ORIGINAL_FRONT":
            front_bytes = payload
        else:
            back_bytes = payload

    if front_bytes is None:
        raise RuntimeError(f"Missing original front image for item {clothing_id}")
    return front_bytes, back_bytes


def _upsert_image(
    db: Session, clothing_id: UUID, image_type: str,
    blob_hash: str, angle: int | None = None,
):
    existing = (
        db.query(Image)
        .filter(
            Image.clothing_item_id == clothing_id,
            Image.image_type == image_type,
            Image.angle == angle,
        )
        .first()
    )
    if existing:
        existing.blob_hash = blob_hash
    else:
        db.add(Image(
            clothing_item_id=clothing_id,
            image_type=image_type,
            blob_hash=blob_hash,
            angle=angle,
        ))
    db.flush()


def _upsert_model(
    db: Session,
    clothing_id: UUID,
    *,
    blob_hash: str,
    vertex_count: int,
    face_count: int,
) -> None:
    existing = db.query(Model3D).filter(Model3D.clothing_item_id == clothing_id).first()
    if existing:
        existing.blob_hash = blob_hash
        existing.vertex_count = vertex_count
        existing.face_count = face_count
    else:
        db.add(Model3D(
            clothing_item_id=clothing_id,
            model_format="glb",
            blob_hash=blob_hash,
            vertex_count=vertex_count,
            face_count=face_count,
        ))
    db.flush()


