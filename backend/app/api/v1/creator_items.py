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
from app.services.creator_processing_task_service import create_processing_task
from app.services.storage_service import StorageService, get_storage_service
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
    storage = get_storage_service()
    front_path = _storage_path(creator_id, item_id, "original_front.jpg")
    back_path = _storage_path(creator_id, item_id, "original_back.jpg") if back_bytes else None
    uploaded_paths: list[str] = []

    try:
        await storage.upload(io.BytesIO(front_bytes), front_path)
        uploaded_paths.append(front_path)
        if back_bytes and back_path:
            await storage.upload(io.BytesIO(back_bytes), back_path)
            uploaded_paths.append(back_path)

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
                storage_path=front_path,
            )
        )
        if back_path:
            db.add(
                CreatorItemImage(
                    creator_item_id=item.id,
                    image_type="ORIGINAL_BACK",
                    storage_path=back_path,
                )
            )
        task = create_processing_task(db, item.id, attempt_no=1)
        db.commit()
    except Exception:
        db.rollback()
        for path in uploaded_paths:
            try:
                await storage.delete(path)
            except Exception:
                logger.warning("Failed to cleanup creator upload %s", path, exc_info=True)
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
    return CreatorItemResponse(data=_to_creator_item_detail(item, get_storage_service()))


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
    return CreatorItemResponse(data=_to_creator_item_detail(updated, get_storage_service()))


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
    crud_creator_item.delete_creator_item(db, item)
    return None


def _to_creator_item_detail(item, storage: StorageService) -> dict:
    images = _build_image_set(item.images, storage)
    model = item.model_3d
    return {
        "id": item.id,
        "creatorId": item.creator_id,
        "catalogVisibility": item.catalog_visibility,
        "processingStatus": item.processing_status,
        "images": images,
        "model3dUrl": storage.get_url(model.storage_path) if model else None,
        "predictedTags": item.predicted_tags or [],
        "finalTags": item.final_tags or [],
        "isConfirmed": item.is_confirmed,
        "name": item.name,
        "description": item.description,
        "customTags": item.custom_tags or [],
        "createdAt": item.created_at,
        "updatedAt": item.updated_at,
    }


def _build_image_set(images: list[CreatorItemImage], storage: StorageService) -> ImageSetResponse:
    result = ImageSetResponse(originalFrontUrl="")
    angle_views: dict[int, str] = {}
    for img in images:
        url = storage.get_url(img.storage_path)
        match img.image_type:
            case "ORIGINAL_FRONT":
                result.originalFrontUrl = url
            case "ORIGINAL_BACK":
                result.originalBackUrl = url
            case "PROCESSED_FRONT":
                result.processedFrontUrl = url
            case "PROCESSED_BACK":
                result.processedBackUrl = url
            case "ANGLE_VIEW" if img.angle is not None:
                angle_views[img.angle] = url
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


def _storage_path(creator_id: UUID, item_id: UUID, filename: str) -> str:
    return f"creators/{creator_id}/{item_id}/{filename}"


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
