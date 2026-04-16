"""
Styled Generation Pipeline

Async Celery pipeline that orchestrates the full DreamO generation flow:
    1. Validate garment asset readiness
    2. Download and preprocess selfie (face validation + bg removal)
    3. Build composite prompt from templates + user scene
    4. Call isolated DreamO HTTP service
    5. Store result image and update database status
"""

import io
import logging
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.clothing_item import Image as ClothingImage
from app.models.styled_generation import StyledGeneration
from app.services.dreamo_client_service import (
    DreamOServiceError,
    call_dreamo_generate,
)
from app.services.prompt_builder_service import build_prompt, get_negative_prompt
from app.services.selfie_preprocessing_service import (
    SelfiePreprocessingError,
    preprocess_selfie,
)
from app.core.config import settings
from app.services.blob_service import get_blob_service
from app.services.blob_storage import get_blob_storage

logger = logging.getLogger(__name__)


def _update_progress(db: Session, gen: StyledGeneration, progress: int):
    gen.progress = progress
    gen.updated_at = datetime.now(timezone.utc)
    db.commit()


async def run_styled_generation_task(generation_id: UUID) -> bool:
    """
    Main pipeline entry point, called from Celery task.

    Returns True on success, raises on failure (Celery will record the error).
    """
    db = SessionLocal()
    blob_storage = get_blob_storage()
    blob_service = get_blob_service()
    try:
        gen = (
            db.query(StyledGeneration)
            .filter(StyledGeneration.id == generation_id)
            .first()
        )
        if gen is None:
            logger.error(
                "StyledGeneration %s not found", generation_id
            )
            return False
        if gen.status != "PENDING":
            logger.info(
                "StyledGeneration %s is %s, skipping",
                generation_id,
                gen.status,
            )
            return False

        # Claim task
        gen.status = "PROCESSING"
        gen.progress = 5
        gen.updated_at = datetime.now(timezone.utc)
        db.commit()

        # Step 1: Validate garment has PROCESSED_FRONT image
        garment_bytes = None
        if gen.source_clothing_item_id:
            processed_img = (
                db.query(ClothingImage)
                .filter(
                    ClothingImage.clothing_item_id
                    == gen.source_clothing_item_id,
                    ClothingImage.image_type == "PROCESSED_FRONT",
                )
                .first()
            )
            if processed_img is None:
                raise RuntimeError(
                    "Garment asset not ready: no processed front image. "
                    "Please wait for clothing processing to complete."
                )
            garment_bytes = await blob_storage.get_bytes(
                processed_img.blob_hash
            )
        _update_progress(db, gen, 15)

        # Step 2: Download and preprocess selfie
        selfie_original_bytes = await blob_storage.get_bytes(
            gen.selfie_original_blob_hash
        )
        try:
            selfie_processed_bytes = await preprocess_selfie(
                selfie_original_bytes
            )
        except SelfiePreprocessingError as e:
            raise RuntimeError(f"Selfie validation failed: {e}")

        proc_blob = await blob_service.ingest_upload(
            db, io.BytesIO(selfie_processed_bytes),
            claimed_mime_type="image/png",
            max_size=settings.SELFIE_MAX_UPLOAD_SIZE_BYTES * 2,
        )
        gen.selfie_processed_blob_hash = proc_blob.blob_hash
        db.commit()
        _update_progress(db, gen, 30)

        # Step 3: Build prompt
        final_prompt = build_prompt(gen.scene_prompt)
        final_negative = get_negative_prompt(gen.negative_prompt)
        _update_progress(db, gen, 35)

        # Step 4: Call DreamO service
        result_bytes, seed_used = await call_dreamo_generate(
            id_image_bytes=selfie_processed_bytes,
            garment_image_bytes=garment_bytes,
            prompt=final_prompt,
            negative_prompt=final_negative,
            guidance_scale=gen.guidance_scale,
            seed=gen.seed,
            width=gen.width,
            height=gen.height,
        )
        _update_progress(db, gen, 90)

        # Step 5: Store result
        result_blob = await blob_service.ingest_upload(
            db, io.BytesIO(result_bytes),
            claimed_mime_type="image/png",
            max_size=settings.SELFIE_MAX_UPLOAD_SIZE_BYTES * 4,
        )

        gen.result_image_blob_hash = result_blob.blob_hash
        gen.seed = seed_used
        gen.status = "SUCCEEDED"
        gen.progress = 100
        gen.updated_at = datetime.now(timezone.utc)
        db.commit()

        logger.info("StyledGeneration %s completed", generation_id)
        return True

    except Exception as exc:
        db.rollback()
        try:
            gen = (
                db.query(StyledGeneration)
                .filter(StyledGeneration.id == generation_id)
                .first()
            )
            if gen is not None:
                gen.status = "FAILED"
                gen.failure_reason = str(exc)[:500]
                gen.updated_at = datetime.now(timezone.utc)
                db.commit()
        except Exception:
            logger.exception(
                "Failed to update error status for %s", generation_id
            )
        logger.exception(
            "StyledGeneration %s failed: %s", generation_id, exc
        )
        return False
    finally:
        db.close()
