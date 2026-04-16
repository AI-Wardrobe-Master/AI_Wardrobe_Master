import io
import logging
from typing import Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.core.config import settings
from app.crud import clothing as crud_clothing
from app.db.session import get_db
from app.models.clothing_item import ClothingItem, Image, Model3D, ProcessingTask
from app.schemas.clothing_item import (
    AngleViewsResponse,
    ClothingItemCreateResponse,
    ClothingItemResponse,
    ClothingItemUpdate,
    ImageSetResponse,
    ProcessingStatusResponse,
)
from app.schemas.search import SearchRequest
from app.services.ai_service import AIService
from app.services.clothing_pipeline import cleanup_pipeline_artifacts
from app.services.processing_task_service import (
    ACTIVE_TASK_STATUSES,
    create_processing_task,
    get_latest_task,
)
from app.services.search_service import SearchService
from app.services.blob_service import get_blob_service
from app.services.blob_storage import get_blob_storage
from app.tasks import process_pipeline

router = APIRouter(prefix="/clothing-items", tags=["clothing"])
logger = logging.getLogger(__name__)


def _build_image_url(item_id: UUID, kind: str) -> str:
    return f"/files/clothing-items/{item_id}/{kind}"


def _item_to_response(item) -> dict:
    return {
        "id": str(item.id),
        "userId": str(item.user_id),
        "source": item.source,
        "predictedTags": item.predicted_tags or [],
        "finalTags": item.final_tags or [],
        "isConfirmed": item.is_confirmed,
        "name": item.name,
        "description": item.description,
        "customTags": item.custom_tags or [],
        "createdAt": item.created_at.isoformat() if item.created_at else None,
        "updatedAt": item.updated_at.isoformat() if item.updated_at else None,
    }


@router.post("", response_model=ClothingItemCreateResponse, status_code=202)
async def create_clothing_item(
    front_image: UploadFile = File(...),
    back_image: UploadFile | None = File(None),
    name: str | None = Form(None),
    description: str | None = Form(None),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    front_bytes = await _read_upload_bytes(front_image, "front_image")
    back_bytes = (
        await _read_upload_bytes(back_image, "back_image")
        if back_image else None
    )
    predicted_tags = AIService().classify_bytes(front_bytes)
    predicted_tag_dicts = [_tag_to_dict(tag) for tag in predicted_tags]
    blob_service = get_blob_service()
    item = ClothingItem(
        id=uuid4(),
        user_id=user_id,
        source="OWNED",
        name=name,
        description=description,
        predicted_tags=predicted_tag_dicts,
        final_tags=list(predicted_tag_dicts),
        is_confirmed=False,
    )

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

        db.add(item)
        db.flush()
        db.add(Image(
            clothing_item_id=item.id,
            image_type="ORIGINAL_FRONT",
            blob_hash=front_blob.blob_hash,
        ))
        if back_blob:
            db.add(Image(
                clothing_item_id=item.id,
                image_type="ORIGINAL_BACK",
                blob_hash=back_blob.blob_hash,
            ))
        task = create_processing_task(db, item.id, attempt_no=1)
        db.commit()
    except Exception:
        db.rollback()
        raise

    _dispatch_processing_task(db, task.id)
    return ClothingItemCreateResponse(
        id=item.id,
        processingTaskId=task.id,
        status=task.status,
        estimatedTime=30,
    )


@router.get("/{item_id}", response_model=ClothingItemResponse)
def get_clothing_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404, "Clothing item not found")

    images = db.query(Image).filter(Image.clothing_item_id == item_id).all()
    model = db.query(Model3D).filter(Model3D.clothing_item_id == item_id).first()

    image_set = _build_image_set(item_id, images)
    return ClothingItemResponse(
        id=item.id,
        userId=item.user_id,
        source=item.source,
        images=image_set,
        model3dUrl=_build_image_url(item_id, "model") if model else None,
        predictedTags=item.predicted_tags or [],
        finalTags=item.final_tags or [],
        isConfirmed=item.is_confirmed,
        name=item.name,
        description=item.description,
        customTags=item.custom_tags or [],
        createdAt=item.created_at,
        updatedAt=item.updated_at,
    )


@router.patch("/{item_id}")
def update_clothing_item(
    item_id: UUID,
    body: ClothingItemUpdate,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = crud_clothing.update(
        db,
        item_id,
        user_id,
        name=body.name,
        description=body.description,
        final_tags=body.final_tags,
        is_confirmed=body.is_confirmed,
        custom_tags=body.custom_tags,
    )
    if not item:
        raise HTTPException(status_code=404, detail="Clothing item not found")
    return {"success": True, "data": _item_to_response(item)}


@router.delete("/{item_id}", status_code=204)
def delete_clothing_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    from app.api.v1.imports import _delete_clothing_item_internal

    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404, "Clothing item not found")

    active = db.query(ProcessingTask).filter(
        ProcessingTask.clothing_item_id == item_id,
        ProcessingTask.status.in_(["PENDING", "PROCESSING"]),
    ).first()
    if active:
        raise HTTPException(409, "Cannot delete while processing")

    _delete_clothing_item_internal(db, item)
    db.commit()


@router.get("")
def list_clothing_items(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
    source: Optional[str] = Query(None),
    tag_key: Optional[str] = Query(None, alias="tagKey"),
    tag_value: Optional[str] = Query(None, alias="tagValue"),
    search: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
):
    items, total = crud_clothing.list_with_tag_filter(
        db,
        user_id,
        source=source,
        tag_key=tag_key,
        tag_value=tag_value,
        search=search,
        page=page,
        limit=limit,
    )
    import math

    total_pages = math.ceil(total / limit) if limit > 0 else 0
    return {
        "success": True,
        "data": {
            "items": [_item_to_response(i) for i in items],
            "pagination": {
                "page": page,
                "limit": limit,
                "total": total,
                "totalPages": total_pages,
            },
        },
    }


@router.post("/search")
def search_clothing_items(
    body: SearchRequest,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    filters = body.filters.model_dump(exclude_none=True) if body.filters else None
    items, total = SearchService().search(
        db,
        user_id,
        query=body.query,
        filters=filters,
        page=body.page,
        limit=body.limit,
    )
    import math

    total_pages = math.ceil(total / body.limit) if body.limit > 0 else 0
    return {
        "success": True,
        "data": {
            "items": [_item_to_response(i) for i in items],
            "pagination": {
                "page": body.page,
                "limit": body.limit,
                "total": total,
                "totalPages": total_pages,
            },
        },
    }


@router.get("/{item_id}/processing-status", response_model=ProcessingStatusResponse)
def get_processing_status(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404, "Clothing item not found")

    task = get_latest_task(db, item_id)
    if not task:
        raise HTTPException(404, "No processing task found")

    steps = _progress_to_steps(task.progress, task.status)
    return ProcessingStatusResponse(
        status=task.status,
        progress=task.progress,
        steps=steps,
        errorMessage=task.error_message,
    )


@router.post("/{item_id}/retry", response_model=ClothingItemCreateResponse, status_code=202)
async def retry_processing(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = (
        db.query(ClothingItem)
        .filter(ClothingItem.id == item_id, ClothingItem.user_id == user_id)
        .with_for_update()
        .first()
    )
    if not item:
        raise HTTPException(404, "Clothing item not found")

    last_task = get_latest_task(db, item_id)
    if last_task is None:
        raise HTTPException(400, "No failed task available to retry")
    if last_task.status in ACTIVE_TASK_STATUSES:
        raise HTTPException(409, "Processing is already active for this item")
    if last_task.status != "FAILED":
        raise HTTPException(400, "Only failed tasks can be retried")

    await cleanup_pipeline_artifacts(db, item.id, commit=False)
    try:
        task = create_processing_task(
            db,
            item.id,
            attempt_no=last_task.attempt_no + 1,
            retry_of_task_id=last_task.id,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Processing is already active for this item")

    _dispatch_processing_task(db, task.id)
    return ClothingItemCreateResponse(
        id=item.id,
        processingTaskId=task.id,
        status=task.status,
        estimatedTime=30,
    )


@router.get("/{item_id}/angle-views", response_model=AngleViewsResponse)
def get_angle_views(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404, "Clothing item not found")

    images = (
        db.query(Image)
        .filter(Image.clothing_item_id == item_id, Image.image_type == "ANGLE_VIEW")
        .order_by(Image.angle)
        .all()
    )
    views = {
        img.angle: _build_image_url(item_id, f"angle-{img.angle}")
        for img in images
        if img.angle is not None
    }
    return AngleViewsResponse(angleViews=views)


@router.get("/{item_id}/model")
async def download_model(
    item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = crud_clothing.get(db, item_id, user_id)
    if not item:
        raise HTTPException(404, "Clothing item not found")

    model = db.query(Model3D).filter(Model3D.clothing_item_id == item_id).first()
    if not model:
        raise HTTPException(404, "3D model not found")

    blob_storage = get_blob_storage()
    data = await blob_storage.get_bytes(model.blob_hash)

    from fastapi.responses import Response

    return Response(
        content=data,
        media_type="model/gltf-binary",
        headers={"Content-Disposition": f"attachment; filename={item_id}.glb"},
    )


def _build_image_set(item_id: UUID, images: list[Image]) -> ImageSetResponse:
    result = ImageSetResponse(originalFrontUrl="")
    angle_views: dict[int, str] = {}

    for img in images:
        match img.image_type:
            case "ORIGINAL_FRONT":
                result.originalFrontUrl = _build_image_url(item_id, "original-front")
            case "ORIGINAL_BACK":
                result.originalBackUrl = _build_image_url(item_id, "original-back")
            case "PROCESSED_FRONT":
                result.processedFrontUrl = _build_image_url(item_id, "processed-front")
            case "PROCESSED_BACK":
                result.processedBackUrl = _build_image_url(item_id, "processed-back")
            case "ANGLE_VIEW" if img.angle is not None:
                angle_views[img.angle] = _build_image_url(item_id, f"angle-{img.angle}")

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


def _dispatch_processing_task(db: Session, task_id: UUID) -> None:
    try:
        process_pipeline.delay(str(task_id))
    except Exception as exc:
        logger.exception("Failed to dispatch processing task %s", task_id)
        task = db.query(ProcessingTask).filter(ProcessingTask.id == task_id).first()
        if task is not None:
            task.status = "FAILED"
            task.error_message = f"Task dispatch failed: {exc}"[:500]
            db.commit()
        raise HTTPException(503, "Processing queue is unavailable")


def _progress_to_steps(progress: int, status: str) -> dict[str, str]:
    if status == "FAILED":
        return {
            "upload": "completed",
            "classification": "completed",
            "backgroundRemoval": "failed",
            "modelGeneration": "pending",
            "angleRendering": "pending",
        }

    def _s(threshold: int) -> str:
        if progress >= threshold + 20:
            return "completed"
        if progress >= threshold:
            return "processing"
        return "pending"

    return {
        "upload": "completed" if progress >= 5 else "processing",
        "classification": "completed",
        "backgroundRemoval": _s(15),
        "modelGeneration": _s(30),
        "angleRendering": _s(70),
    }


def _tag_to_dict(tag) -> dict[str, str]:
    if isinstance(tag, dict):
        return tag
    return {"key": tag.key, "value": tag.value}
