"""
Full clothing digitalization pipeline:
  upload → background removal → 3D generation → angle rendering → persist
"""
import io
import logging
from datetime import datetime, timezone
from uuid import UUID, uuid4

from sqlalchemy.orm import Session

from app.models.clothing_item import ClothingItem, Image, Model3D, ProcessingTask
from app.services import background_removal_service as bg
from app.services import model_3d_service as m3d
from app.services import angle_renderer_service as renderer
from app.services.storage_service import StorageService

logger = logging.getLogger(__name__)


async def run_pipeline(
    db: Session,
    storage: StorageService,
    user_id: UUID,
    front_bytes: bytes,
    back_bytes: bytes | None,
    name: str | None = None,
    description: str | None = None,
) -> tuple[ClothingItem, ProcessingTask]:
    """Execute the full pipeline. Returns (item, task)."""

    clothing_id = uuid4()
    item = ClothingItem(
        id=clothing_id, user_id=user_id, source="OWNED",
        name=name, description=description,
        predicted_tags=[], final_tags=[], is_confirmed=False,
    )
    task = ProcessingTask(
        id=uuid4(), clothing_item_id=clothing_id,
        task_type="FULL_PIPELINE", status="PROCESSING", progress=0,
        started_at=datetime.now(timezone.utc),
    )
    db.add(item)
    db.add(task)
    db.commit()

    base = f"{user_id}/{clothing_id}"
    uploaded: list[str] = []

    try:
        # --- 1. Store originals ---
        _update(db, task, 5)
        front_path = f"{base}/original_front.jpg"
        await storage.upload(io.BytesIO(front_bytes), front_path)
        uploaded.append(front_path)
        _add_image(db, clothing_id, "ORIGINAL_FRONT", front_path)

        back_path = None
        if back_bytes:
            back_path = f"{base}/original_back.jpg"
            await storage.upload(io.BytesIO(back_bytes), back_path)
            uploaded.append(back_path)
            _add_image(db, clothing_id, "ORIGINAL_BACK", back_path)

        # --- 2. Background removal ---
        _update(db, task, 15)
        front_proc = await bg.remove_background(front_bytes)
        proc_front_path = f"{base}/processed_front.png"
        await storage.upload(io.BytesIO(front_proc), proc_front_path)
        uploaded.append(proc_front_path)
        _add_image(db, clothing_id, "PROCESSED_FRONT", proc_front_path)

        back_proc = None
        if back_bytes:
            back_proc = await bg.remove_background(back_bytes)
            proc_back_path = f"{base}/processed_back.png"
            await storage.upload(io.BytesIO(back_proc), proc_back_path)
            uploaded.append(proc_back_path)
            _add_image(db, clothing_id, "PROCESSED_BACK", proc_back_path)

        # --- 3. 3D model generation ---
        _update(db, task, 30)
        mesh = await m3d.generate_3d_model(front_proc, back_proc)
        _update(db, task, 65)

        glb_bytes = m3d.export_mesh(mesh, "glb")
        model_path = f"{base}/model.glb"
        await storage.upload(io.BytesIO(glb_bytes), model_path)
        uploaded.append(model_path)

        model_record = Model3D(
            clothing_item_id=clothing_id,
            model_format="glb", storage_path=model_path,
            vertex_count=len(mesh.vertices), face_count=len(mesh.faces),
            file_size=len(glb_bytes),
        )
        db.add(model_record)

        # --- 4. Angle rendering ---
        _update(db, task, 70)
        angle_images = renderer.render_all_angles(mesh)

        for angle_deg, png_bytes in angle_images.items():
            angle_path = f"{base}/angle_{angle_deg:03d}.png"
            await storage.upload(io.BytesIO(png_bytes), angle_path)
            uploaded.append(angle_path)
            _add_image(
                db, clothing_id, "ANGLE_VIEW", angle_path, angle=angle_deg
            )
        _update(db, task, 95)

        # --- Done ---
        task.status = "COMPLETED"
        task.progress = 100
        task.completed_at = datetime.now(timezone.utc)
        db.commit()

        logger.info("Pipeline complete for item %s", clothing_id)
        return item, task

    except Exception as exc:
        task.status = "FAILED"
        task.error_message = str(exc)[:500]
        task.completed_at = datetime.now(timezone.utc)
        db.commit()
        logger.exception("Pipeline failed for item %s", clothing_id)
        raise


def _update(db: Session, task: ProcessingTask, progress: int):
    task.progress = progress
    db.commit()


def _add_image(
    db: Session, clothing_id: UUID, image_type: str,
    path: str, angle: int | None = None,
):
    db.add(Image(
        clothing_item_id=clothing_id,
        image_type=image_type,
        storage_path=path,
        angle=angle,
    ))
    db.commit()
