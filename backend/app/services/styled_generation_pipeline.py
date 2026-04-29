"""
Styled Generation Pipeline

Async Celery pipeline that orchestrates the full DreamO generation flow:
    1. Validate garment junction rows ready (PROCESSED_FRONT for each item)
    2. Download and preprocess selfie (face validation + bg removal)
    3. Build composite prompt from templates + user scene (multi-garment)
    4. Call isolated DreamO HTTP service with list of garment images
    5. Store result image and update database status
"""

import io
import logging
import os
import socket
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.clothing_item import Image as ClothingImage
from app.models.styled_generation import (
    StyledGeneration,
    StyledGenerationClothingItem,
)
from app.services.dreamo_client_service import (
    DreamOServiceError,
    call_dreamo_generate,
)
from app.services.prompt_builder_service import (
    SLOT_DEFAULT_DESCRIPTOR,
    build_prompt,
    get_negative_prompt,
)
from app.services.selfie_preprocessing_service import (
    SelfiePreprocessingError,
    preprocess_selfie,
)
from app.core.config import settings
from app.services.blob_service import get_blob_service
from app.services.blob_storage import get_blob_storage

logger = logging.getLogger(__name__)

LEASE_DURATION = timedelta(minutes=15)

_SLOT_ORDER_MAP = {"HAT": 1, "TOP": 2, "PANTS": 3, "SHOES": 4}


def _update_progress(db: Session, gen: StyledGeneration, progress: int):
    gen.progress = progress
    now = datetime.now(timezone.utc)
    gen.updated_at = now
    gen.lease_expires_at = now + LEASE_DURATION
    db.commit()


def _resolve_descriptor(ci, slot: str) -> str:
    """Prefer name; fall back to category; finally slot default."""
    if ci.name and ci.name.strip():
        return ci.name.strip()
    if ci.category and ci.category.strip():
        return ci.category.strip()
    return SLOT_DEFAULT_DESCRIPTOR.get(slot, "clothing")


async def run_styled_generation_task(generation_id: UUID) -> bool:
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
            logger.error("StyledGeneration %s not found", generation_id)
            return False
        if gen.status != "PENDING":
            logger.info(
                "StyledGeneration %s is %s, skipping",
                generation_id, gen.status,
            )
            return False

        # Claim task + set lease.
        now = datetime.now(timezone.utc)
        gen.status = "PROCESSING"
        gen.started_at = now
        gen.lease_expires_at = now + LEASE_DURATION
        gen.worker_id = socket.gethostname()[:255]
        gen.progress = 5
        gen.updated_at = now
        db.commit()

        # Step 1: fetch garments via junction in slot order.
        junction_rows = (
            db.query(StyledGenerationClothingItem)
            .filter_by(generation_id=generation_id)
            .all()
        )
        junction_rows.sort(key=lambda jr: _SLOT_ORDER_MAP.get(jr.slot, 99))

        if not junction_rows:
            raise RuntimeError("No garments attached to this generation")

        garments_bytes: list[bytes] = []
        garments_for_prompt: list[tuple[str, str]] = []

        for jr in junction_rows:
            ci = jr.clothing_item
            if ci is None or ci.deleted_at is not None:
                raise RuntimeError(
                    f"Clothing item for slot {jr.slot} is not available "
                    f"(deleted or removed)"
                )
            img = (
                db.query(ClothingImage)
                .filter_by(clothing_item_id=ci.id, image_type="PROCESSED_FRONT")
                .first()
            )
            if img is None:
                raise RuntimeError(
                    f"Clothing item {ci.id} (slot {jr.slot}) has no PROCESSED_FRONT image"
                )
            garments_bytes.append(await blob_storage.get_bytes(img.blob_hash))
            garments_for_prompt.append(
                (jr.slot, _resolve_descriptor(ci, jr.slot))
            )

        _update_progress(db, gen, 15)

        # Step 2: download + preprocess selfie.
        selfie_original_bytes = await blob_storage.get_bytes(
            gen.selfie_original_blob_hash
        )
        try:
            selfie_processed_bytes = await preprocess_selfie(selfie_original_bytes)
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

        # Step 3: build prompt (new signature).
        final_prompt = build_prompt(
            gen.scene_prompt, gen.gender, garments_for_prompt
        )
        final_negative = get_negative_prompt(gen.negative_prompt)
        _update_progress(db, gen, 35)

        # Step 4: DreamO call with list of garment bytes.
        result_bytes, seed_used = await call_dreamo_generate(
            id_image_bytes=selfie_processed_bytes,
            garment_images_bytes=garments_bytes,
            prompt=final_prompt,
            negative_prompt=final_negative,
            guidance_scale=gen.guidance_scale,
            seed=gen.seed,
            width=gen.width,
            height=gen.height,
            num_inference_steps=settings.DREAMO_DEFAULT_STEPS,
        )
        _update_progress(db, gen, 90)

        # Step 5: store result.
        result_blob = await blob_service.ingest_upload(
            db, io.BytesIO(result_bytes),
            claimed_mime_type="image/png",
            max_size=settings.SELFIE_MAX_UPLOAD_SIZE_BYTES * 4,
        )
        gen.result_image_blob_hash = result_blob.blob_hash
        gen.seed = seed_used
        gen.status = "SUCCEEDED"
        gen.progress = 100
        now = datetime.now(timezone.utc)
        gen.updated_at = now
        gen.lease_expires_at = None  # clear lease on success
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
                gen.lease_expires_at = None
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
