import io
import logging
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.api.deps import get_current_creator_user_id
from app.core.config import settings
from app.crud import card_pack as crud_card_pack
from app.crud import creator_item as crud_creator_item
from app.db.session import get_db
from app.models.creator import CreatorItemImage, CreatorProcessingTask
from app.schemas.clothing_item import ImageSetResponse
from app.schemas.creator import (
    CreatorItemCreateResponse,
    CreatorItemCreateResponseData,
    CreatorItemResponse,
    CreatorItemUpdate,
)
from app.services.blob_service import get_blob_service
from app.services.creator_processing_task_service import create_processing_task
from app.tasks import process_creator_pipeline

router = APIRouter(prefix="/creator-items", tags=["creator-items"])
logger = logging.getLogger(__name__)


@router.post("", response_model=CreatorItemCreateResponse, status_code=202)
async def create_creator_item(
    front_image: UploadFile = File(...),
    back_image: UploadFile | None = File(None),
    name: str | None = Form(None),
    description: str | None = Form(None),
    catalog_visibility: str = Form("PACK_ONLY", alias="catalogVisibility"),
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    front_bytes = await _read_upload_bytes(front_image, "front_image")
    back_bytes = await _read_upload_bytes(back_image, "back_image") if back_image else None
    item_id = uuid4()
    blob_service = get_blob_service()

    try:
        front_blob = await blob_service.ingest_upload(
            db, io.BytesIO(front_bytes),
            claimed_mime_type=front_image.content_type or "image/jpeg",
            max_size=settings.MAX_UPLOAD_SIZE_BYTES,
        )
        back_blob = None
        if back_bytes:
            back_blob = await blob_service.ingest_upload(
                db, io.BytesIO(back_bytes),
                claimed_mime_type=back_image.content_type or "image/jpeg",
                max_size=settings.MAX_UPLOAD_SIZE_BYTES,
            )

        item = crud_creator_item.create_creator_item(
            db,
            item_id=item_id,
            creator_id=creator_id,
            name=name,
            description=description,
            catalog_visibility=_validate_catalog_visibility(catalog_visibility),
        )
        db.add(
            CreatorItemImage(
                creator_item_id=item.id,
                image_type="ORIGINAL_FRONT",
                blob_hash=front_blob.blob_hash,
            )
        )
        if back_blob:
            db.add(
                CreatorItemImage(
                    creator_item_id=item.id,
                    image_type="ORIGINAL_BACK",
                    blob_hash=back_blob.blob_hash,
                )
            )
        task = create_processing_task(db, item.id, attempt_no=1)
        db.commit()
    except Exception:
        db.rollback()
        raise

    _dispatch_processing_task(db, task.id)
    return CreatorItemCreateResponse(
        data=CreatorItemCreateResponseData(
            id=item.id,
            processingTaskId=task.id,
            status=task.status,
            catalogVisibility=item.catalog_visibility,
            createdAt=item.created_at,
        )
    )


@router.get("/{item_id}", response_model=CreatorItemResponse)
def get_creator_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    item = crud_creator_item.get_owned_creator_item(
        db,
        item_id=item_id,
        creator_id=creator_id,
    )
    if item is None:
        raise HTTPException(404, "Creator item not found")
    return CreatorItemResponse(data=_to_creator_item_detail(item))


@router.patch("/{item_id}", response_model=CreatorItemResponse)
def update_creator_item(
    item_id: UUID,
    body: CreatorItemUpdate,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    item = crud_creator_item.get_owned_creator_item(
        db,
        item_id=item_id,
        creator_id=creator_id,
    )
    if item is None:
        raise HTTPException(404, "Creator item not found")
    updated = crud_creator_item.update_creator_item(
        db,
        item,
        name=body.name,
        description=body.description,
        final_tags=[
            {"key": tag.key, "value": tag.value} for tag in body.final_tags
        ] if body.final_tags is not None else None,
        custom_tags=body.custom_tags,
        catalog_visibility=_validate_catalog_visibility(body.catalog_visibility)
        if body.catalog_visibility is not None
        else None,
    )
    return CreatorItemResponse(data=_to_creator_item_detail(updated))


@router.delete("/{item_id}", status_code=204)
def delete_creator_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    item = crud_creator_item.get_owned_creator_item(
        db,
        item_id=item_id,
        creator_id=creator_id,
        for_update=True,
    )
    if item is None:
        raise HTTPException(404, "Creator item not found")
    if crud_card_pack.has_published_pack_reference(db, creator_item_id=item_id):
        raise HTTPException(
            409,
            "Creator item belongs to a published pack. Delete the published pack first.",
        )
    blob_service = get_blob_service()
    blob_hashes = [img.blob_hash for img in item.images if img.blob_hash]
    if item.model_3d and item.model_3d.blob_hash:
        blob_hashes.append(item.model_3d.blob_hash)
    db.delete(item)
    db.flush()
    for h in blob_hashes:
        blob_service.release(db, h)
    db.commit()
    return None


def _to_creator_item_detail(item) -> dict:
    images = _build_image_set(item.id, item.images)
    model = item.model_3d
    return {
        "id": item.id,
        "creatorId": item.creator_id,
        "catalogVisibility": item.catalog_visibility,
        "processingStatus": item.processing_status,
        "images": images,
        "model3dUrl": f"/files/creator-items/{item.id}/model" if model else None,
        "predictedTags": item.predicted_tags or [],
        "finalTags": item.final_tags or [],
        "isConfirmed": item.is_confirmed,
        "name": item.name,
        "description": item.description,
        "customTags": item.custom_tags or [],
        "createdAt": item.created_at,
        "updatedAt": item.updated_at,
    }


_IMAGE_TYPE_TO_KIND = {
    "ORIGINAL_FRONT": "original-front",
    "ORIGINAL_BACK": "original-back",
    "PROCESSED_FRONT": "processed-front",
    "PROCESSED_BACK": "processed-back",
}


def _build_image_set(item_id: UUID, images: list[CreatorItemImage]) -> ImageSetResponse:
    result = ImageSetResponse(originalFrontUrl="")
    angle_views: dict[int, str] = {}
    for img in images:
        if img.image_type == "ANGLE_VIEW" and img.angle is not None:
            angle_views[img.angle] = f"/files/creator-items/{item_id}/angle-{img.angle}"
        else:
            kind = _IMAGE_TYPE_TO_KIND.get(img.image_type)
            if kind is None:
                continue
            url = f"/files/creator-items/{item_id}/{kind}"
            match img.image_type:
                case "ORIGINAL_FRONT":
                    result.originalFrontUrl = url
                case "ORIGINAL_BACK":
                    result.originalBackUrl = url
                case "PROCESSED_FRONT":
                    result.processedFrontUrl = url
                case "PROCESSED_BACK":
                    result.processedBackUrl = url
    result.angleViews = angle_views
    return result


async def _read_upload_bytes(file: UploadFile, field_name: str) -> bytes:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(422, f"{field_name} must be an image")
    payload = await file.read()
    if not payload:
        raise HTTPException(422, f"{field_name} is empty")
    if len(payload) > settings.MAX_UPLOAD_SIZE_BYTES:
        raise HTTPException(
            413,
            f"{field_name} exceeds the {settings.MAX_UPLOAD_SIZE_BYTES} byte limit",
        )
    return payload


def _validate_catalog_visibility(value: str) -> str:
    normalized = value.strip().upper()
    if normalized not in {"PRIVATE", "PACK_ONLY", "PUBLIC"}:
        raise HTTPException(422, "Invalid catalogVisibility")
    return normalized


def _dispatch_processing_task(db: Session, task_id: UUID) -> None:
    try:
        process_creator_pipeline.delay(str(task_id))
    except Exception as exc:
        logger.exception("Failed to dispatch creator processing task %s", task_id)
        task = (
            db.query(CreatorProcessingTask)
            .filter(CreatorProcessingTask.id == task_id)
            .first()
        )
        if task is not None:
            task.status = "FAILED"
            task.error_message = f"Task dispatch failed: {exc}"[:500]
            db.commit()
        raise HTTPException(503, "Processing queue is unavailable")
