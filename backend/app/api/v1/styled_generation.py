"""
Styled Generation API — personalized scene outfit generation via DreamO.

POST   /styled-generations          Create a new generation task
GET    /styled-generations          List user's generation history
GET    /styled-generations/{id}     Get generation detail
POST   /styled-generations/{id}/retry  Retry a failed generation
DELETE /styled-generations/{id}     Delete a generation
"""

import io
import json
import logging
import math
from uuid import UUID, uuid4

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
)
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.core.config import settings
from app.crud import clothing as crud_clothing
from app.crud import styled_generation as crud_sg
from app.db.session import get_db
from app.models.clothing_item import Image as ClothingImage
from app.models.styled_generation import (
    StyledGeneration,
    StyledGenerationClothingItem,
)
from app.schemas.styled_generation import (
    StyledGenerationCreateResponse,
    StyledGenerationGarmentSummary,
    StyledGenerationResponse,
)
from app.services.blob_service import get_blob_service
from app.tasks import run_styled_generation

router = APIRouter(prefix="/styled-generations", tags=["Styled Generation"])
logger = logging.getLogger(__name__)


# ── helpers ──────────────────────────────────────────────────────────


def _to_response(gen: StyledGeneration) -> dict:
    garments_list = [
        {
            "id": jr.clothing_item_id,
            "slot": jr.slot,
            "name": jr.clothing_item.name if jr.clothing_item else None,
            "imageUrl": (
                f"/files/clothing-items/{jr.clothing_item_id}/processed-front"
                if jr.clothing_item else None
            ),
        }
        for jr in gen.garments
    ]
    return StyledGenerationResponse(
        id=gen.id,
        userId=gen.user_id,
        sourceClothingItemId=gen.source_clothing_item_id,
        selfieOriginalUrl=f"/files/styled-generations/{gen.id}/selfie-original",
        selfieProcessedUrl=(
            f"/files/styled-generations/{gen.id}/selfie-processed"
            if gen.selfie_processed_blob_hash
            else None
        ),
        scenePrompt=gen.scene_prompt,
        negativePrompt=gen.negative_prompt,
        dreamoVersion=gen.dreamo_version,
        status=gen.status,
        progress=gen.progress,
        resultImageUrl=(
            f"/files/styled-generations/{gen.id}/result"
            if gen.result_image_blob_hash
            else None
        ),
        failureReason=gen.failure_reason,
        guidanceScale=gen.guidance_scale,
        seed=gen.seed,
        width=gen.width,
        height=gen.height,
        gender=gen.gender,
        garments=garments_list,
        createdAt=gen.created_at,
        updatedAt=gen.updated_at,
    ).model_dump()


def _dispatch(gen_id: UUID) -> None:
    """Dispatch styled generation task to Celery queue."""
    run_styled_generation.apply_async(
        args=[str(gen_id)],
        queue="styled_generation",
    )


# ── endpoints ────────────────────────────────────────────────────────


@router.post("", status_code=202)
async def create_styled_generation(
    selfie_image: UploadFile = File(...),
    gender: str = Form(...),
    scene_prompt: str = Form(...),
    clothing_items: str | None = Form(None),        # NEW: JSON string
    clothing_item_id: str | None = Form(None),      # DEPRECATED: single-item shim
    negative_prompt: str | None = Form(None),
    guidance_scale: float = Form(4.5),
    seed: int = Form(-1),
    width: int = Form(1024),
    height: int = Form(1024),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Create a new DreamO styled generation task."""
    # Selfie validation (preserved from existing code).
    if (
        not selfie_image.content_type
        or not selfie_image.content_type.startswith("image/")
    ):
        raise HTTPException(422, "selfie_image must be an image file")

    selfie_bytes = await selfie_image.read()
    if not selfie_bytes:
        raise HTTPException(422, "selfie_image is empty")
    if len(selfie_bytes) > settings.SELFIE_MAX_UPLOAD_SIZE_BYTES:
        raise HTTPException(413, "selfie_image exceeds size limit (10 MB)")

    # Gender validation.
    gender_norm = gender.strip().upper()
    if gender_norm not in ("MALE", "FEMALE"):
        raise HTTPException(422, "gender must be 'male' or 'female'")

    # Parse clothing_items (new) or fall back to clothing_item_id (legacy).
    if clothing_items:
        try:
            items_parsed = json.loads(clothing_items)
        except json.JSONDecodeError:
            raise HTTPException(422, "clothing_items must be valid JSON")
    elif clothing_item_id:
        items_parsed = [{"id": clothing_item_id, "slot": "TOP"}]
    else:
        raise HTTPException(422, "clothing_items is required")

    if not isinstance(items_parsed, list) or not (1 <= len(items_parsed) <= 4):
        raise HTTPException(422, "clothing_items must be a JSON array of 1 to 4 items")

    seen_slots: set[str] = set()
    parsed: list[tuple[UUID, str]] = []
    for entry in items_parsed:
        if not isinstance(entry, dict):
            raise HTTPException(422, "each clothing_items entry must be an object")
        raw_id = entry.get("id")
        raw_slot = entry.get("slot")
        if raw_id is None or raw_slot is None:
            raise HTTPException(422, "each clothing_items entry needs id and slot")
        try:
            item_uuid = UUID(str(raw_id))
        except ValueError:
            raise HTTPException(422, f"clothing_item id {raw_id!r} is not a UUID")
        slot = str(raw_slot).strip().upper()
        if slot not in ("HAT", "TOP", "PANTS", "SHOES"):
            raise HTTPException(422, f"unknown slot {slot}")
        if slot in seen_slots:
            raise HTTPException(422, f"duplicate slot {slot} in clothing_items")
        seen_slots.add(slot)
        parsed.append((item_uuid, slot))

    # Ensure each item belongs to the user, not tombstoned, and has PROCESSED_FRONT.
    for item_uuid, slot in parsed:
        item = crud_clothing.get(db, item_uuid, user_id)
        if not item:
            raise HTTPException(404, f"Clothing item {item_uuid} not found")

        processed_front = (
            db.query(ClothingImage)
            .filter(
                ClothingImage.clothing_item_id == item_uuid,
                ClothingImage.image_type == "PROCESSED_FRONT",
            )
            .first()
        )
        if not processed_front:
            raise HTTPException(
                409,
                f"Clothing item {item_uuid} (slot {slot}) has not finished processing",
            )

    if width < 768 or width > 1024 or height < 768 or height > 1024:
        raise HTTPException(
            422, "width and height must be between 768 and 1024"
        )

    # Store selfie via CAS.
    blob_service = get_blob_service()
    gen_id = uuid4()
    selfie_blob = await blob_service.ingest_upload(
        db, io.BytesIO(selfie_bytes),
        claimed_mime_type=selfie_image.content_type or "image/jpeg",
        max_size=settings.SELFIE_MAX_UPLOAD_SIZE_BYTES,
    )

    # Create the StyledGeneration row.
    # Keep source_clothing_item_id pointing at TOP (if any) for legacy compat.
    top_item_id: UUID | None = next(
        (iid for iid, slt in parsed if slt == "TOP"), None
    )
    gen = StyledGeneration(
        id=gen_id,
        user_id=user_id,
        source_clothing_item_id=top_item_id,
        selfie_original_blob_hash=selfie_blob.blob_hash,
        scene_prompt=scene_prompt,
        negative_prompt=negative_prompt,
        dreamo_version=settings.DREAMO_DEFAULT_VERSION,
        gender=gender_norm,
        guidance_scale=guidance_scale,
        seed=seed,
        width=width,
        height=height,
        status="PENDING",
        progress=0,
    )
    db.add(gen)

    # Insert junction rows.
    for position, (item_uuid, slot) in enumerate(parsed):
        db.add(StyledGenerationClothingItem(
            generation_id=gen_id,
            clothing_item_id=item_uuid,
            slot=slot,
            position=position,
        ))
    db.commit()

    # Dispatch.
    try:
        _dispatch(gen_id)
    except Exception as exc:
        logger.exception("Failed to dispatch styled generation task")
        gen.status = "FAILED"
        gen.failure_reason = f"Task dispatch failed: {exc}"[:500]
        db.commit()
        raise HTTPException(503, "Processing queue is unavailable")

    return StyledGenerationCreateResponse(
        id=gen_id, status="PENDING", estimatedTime=120
    )


@router.get("/{gen_id}")
def get_styled_generation(
    gen_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Get a styled generation by ID."""
    gen = crud_sg.get(db, gen_id, user_id)
    if not gen:
        raise HTTPException(404, "Styled generation not found")
    return {"success": True, "data": _to_response(gen)}


@router.get("")
def list_styled_generations(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List the current user's styled generation history."""
    items, total = crud_sg.list_by_user(
        db, user_id, page=page, limit=limit
    )
    total_pages = math.ceil(total / limit) if limit > 0 else 0
    return {
        "success": True,
        "data": {
            "items": [_to_response(g) for g in items],
            "pagination": {
                "page": page,
                "limit": limit,
                "total": total,
                "totalPages": total_pages,
            },
        },
    }


@router.post("/{gen_id}/retry", status_code=202)
def retry_styled_generation(
    gen_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Retry a failed styled generation."""
    gen = crud_sg.get(db, gen_id, user_id)
    if not gen:
        raise HTTPException(404, "Styled generation not found")
    if gen.status != "FAILED":
        raise HTTPException(400, "Only failed generations can be retried")

    blob_service = get_blob_service()
    for hash_col in ("result_image_blob_hash", "selfie_processed_blob_hash"):
        h = getattr(gen, hash_col)
        if h:
            blob_service.release(db, h)
            setattr(gen, hash_col, None)

    gen.status = "PENDING"
    gen.progress = 0
    gen.failure_reason = None
    db.commit()

    try:
        _dispatch(gen_id)
    except Exception as exc:
        logger.exception("Failed to dispatch retry task")
        gen.status = "FAILED"
        gen.failure_reason = f"Task dispatch failed: {exc}"[:500]
        db.commit()
        raise HTTPException(503, "Processing queue is unavailable")

    return StyledGenerationCreateResponse(
        id=gen.id, status="PENDING", estimatedTime=120
    )


@router.delete("/{gen_id}", status_code=204)
async def delete_styled_generation(
    gen_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Delete a styled generation and its stored files."""
    gen = crud_sg.get(db, gen_id, user_id)
    if not gen:
        raise HTTPException(404, "Styled generation not found")
    if gen.status in ("PENDING", "PROCESSING"):
        raise HTTPException(
            409, "Cannot delete a generation that is still processing"
        )

    # Release blob references (GC will clean up physical bytes)
    blob_service = get_blob_service()
    for blob_hash in [
        gen.selfie_original_blob_hash,
        gen.selfie_processed_blob_hash,
        gen.result_image_blob_hash,
    ]:
        if blob_hash:
            try:
                blob_service.release(db, blob_hash)
            except Exception:
                logger.warning("Failed to release blob: %s", blob_hash)

    db.delete(gen)
    db.commit()
