"""
Styled Generation API — personalized scene outfit generation via DreamO.

POST   /styled-generations          Create a new generation task
GET    /styled-generations          List user's generation history
GET    /styled-generations/{id}     Get generation detail
POST   /styled-generations/{id}/retry  Retry a failed generation
DELETE /styled-generations/{id}     Delete a generation
"""

import io
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
from app.models.styled_generation import StyledGeneration
from app.schemas.styled_generation import (
    StyledGenerationCreateResponse,
    StyledGenerationResponse,
)
from app.services.storage_service import get_storage_service
from app.tasks import run_styled_generation

router = APIRouter(prefix="/styled-generations", tags=["Styled Generation"])
logger = logging.getLogger(__name__)


# ── helpers ──────────────────────────────────────────────────────────


def _to_response(gen: StyledGeneration) -> dict:
    storage = get_storage_service()
    return StyledGenerationResponse(
        id=gen.id,
        userId=gen.user_id,
        sourceClothingItemId=gen.source_clothing_item_id,
        selfieOriginalUrl=storage.get_url(gen.selfie_original_path),
        selfieProcessedUrl=(
            storage.get_url(gen.selfie_processed_path)
            if gen.selfie_processed_path
            else None
        ),
        scenePrompt=gen.scene_prompt,
        negativePrompt=gen.negative_prompt,
        dreamoVersion=gen.dreamo_version,
        status=gen.status,
        progress=gen.progress,
        resultImageUrl=(
            storage.get_url(gen.result_image_path)
            if gen.result_image_path
            else None
        ),
        failureReason=gen.failure_reason,
        guidanceScale=gen.guidance_scale,
        seed=gen.seed,
        width=gen.width,
        height=gen.height,
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
    clothing_item_id: str = Form(...),
    scene_prompt: str = Form(...),
    negative_prompt: str | None = Form(None),
    guidance_scale: float = Form(4.5),
    seed: int = Form(-1),
    width: int = Form(1024),
    height: int = Form(1024),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Create a new DreamO styled generation task."""
    # Validate selfie upload
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

    # Validate clothing item
    try:
        item_uuid = UUID(clothing_item_id)
    except ValueError:
        raise HTTPException(422, "clothing_item_id must be a valid UUID")

    item = crud_clothing.get(db, item_uuid, user_id)
    if not item:
        raise HTTPException(404, "Clothing item not found")

    # Check garment has PROCESSED_FRONT image
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
            "Clothing item has not finished processing. "
            "Please wait until background removal is complete before "
            "creating a styled generation.",
        )

    # Validate dimensions
    if width < 768 or width > 1024 or height < 768 or height > 1024:
        raise HTTPException(
            422, "width and height must be between 768 and 1024"
        )

    # Store selfie original
    storage = get_storage_service()
    gen_id = uuid4()
    selfie_path = f"{user_id}/styled-generations/{gen_id}/selfie_original.jpg"
    await storage.upload(io.BytesIO(selfie_bytes), selfie_path)

    # Create DB record
    gen = StyledGeneration(
        id=gen_id,
        user_id=user_id,
        source_clothing_item_id=item_uuid,
        selfie_original_path=selfie_path,
        scene_prompt=scene_prompt,
        negative_prompt=negative_prompt,
        dreamo_version=settings.DREAMO_DEFAULT_VERSION,
        guidance_scale=guidance_scale,
        seed=seed,
        width=width,
        height=height,
        status="PENDING",
        progress=0,
    )
    db.add(gen)
    db.commit()

    # Dispatch Celery task
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
        raise HTTPException(
            400, "Only failed generations can be retried"
        )

    gen.status = "PENDING"
    gen.progress = 0
    gen.failure_reason = None
    gen.result_image_path = None
    gen.selfie_processed_path = None
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

    # Clean up storage
    storage = get_storage_service()
    for path in [
        gen.selfie_original_path,
        gen.selfie_processed_path,
        gen.result_image_path,
    ]:
        if path:
            try:
                await storage.delete(path)
            except Exception:
                logger.warning("Failed to delete storage path: %s", path)

    db.delete(gen)
    db.commit()
