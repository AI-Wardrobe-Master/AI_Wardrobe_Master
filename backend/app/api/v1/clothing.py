from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.clothing_item import ClothingItem, Image, Model3D, ProcessingTask
from app.schemas.clothing_item import (
    AngleViewsResponse,
    ClothingItemCreateResponse,
    ClothingItemResponse,
    ImageSetResponse,
    ProcessingStatusResponse,
)
from app.services.clothing_pipeline import run_pipeline
from app.services.storage_service import StorageService, get_storage_service

router = APIRouter(prefix="/clothing-items", tags=["clothing"])


def _storage() -> StorageService:
    return get_storage_service()


# ---- POST /clothing-items ----

@router.post("", response_model=ClothingItemCreateResponse, status_code=202)
async def create_clothing_item(
    front_image: UploadFile = File(...),
    back_image: UploadFile | None = File(None),
    name: str | None = Form(None),
    description: str | None = Form(None),
    db: Session = Depends(get_db),
):
    front_bytes = await front_image.read()
    back_bytes = await back_image.read() if back_image else None
    storage = _storage()

    # TODO: move to Celery for true async; for now run inline
    item, task = await run_pipeline(
        db, storage,
        user_id=UUID("00000000-0000-0000-0000-000000000001"),  # placeholder until auth
        front_bytes=front_bytes,
        back_bytes=back_bytes,
        name=name,
        description=description,
    )
    return ClothingItemCreateResponse(
        id=item.id, processingTaskId=task.id,
        status=task.status, estimatedTime=30,
    )


# ---- GET /clothing-items/:id ----

@router.get("/{item_id}", response_model=ClothingItemResponse)
def get_clothing_item(item_id: UUID, db: Session = Depends(get_db)):
    item = db.query(ClothingItem).filter(ClothingItem.id == item_id).first()
    if not item:
        raise HTTPException(404, "Clothing item not found")

    storage = _storage()
    images = db.query(Image).filter(Image.clothing_item_id == item_id).all()
    model = db.query(Model3D).filter(Model3D.clothing_item_id == item_id).first()

    image_set = _build_image_set(images, storage)
    return ClothingItemResponse(
        id=item.id, userId=item.user_id, source=item.source,
        images=image_set,
        model3dUrl=storage.get_url(model.storage_path) if model else None,
        predictedTags=item.predicted_tags or [],
        finalTags=item.final_tags or [],
        isConfirmed=item.is_confirmed,
        name=item.name, description=item.description,
        createdAt=item.created_at, updatedAt=item.updated_at,
    )


# ---- GET /clothing-items/:id/processing-status ----

@router.get("/{item_id}/processing-status", response_model=ProcessingStatusResponse)
def get_processing_status(item_id: UUID, db: Session = Depends(get_db)):
    task = (
        db.query(ProcessingTask)
        .filter(ProcessingTask.clothing_item_id == item_id)
        .order_by(ProcessingTask.created_at.desc())
        .first()
    )
    if not task:
        raise HTTPException(404, "No processing task found")

    steps = _progress_to_steps(task.progress, task.status)
    return ProcessingStatusResponse(
        status=task.status, progress=task.progress,
        steps=steps, errorMessage=task.error_message,
    )


# ---- POST /clothing-items/:id/retry ----

@router.post("/{item_id}/retry", response_model=ClothingItemCreateResponse, status_code=202)
async def retry_processing(item_id: UUID, db: Session = Depends(get_db)):
    item = db.query(ClothingItem).filter(ClothingItem.id == item_id).first()
    if not item:
        raise HTTPException(404, "Clothing item not found")

    last_task = (
        db.query(ProcessingTask)
        .filter(ProcessingTask.clothing_item_id == item_id)
        .order_by(ProcessingTask.created_at.desc())
        .first()
    )
    if last_task and last_task.status != "FAILED":
        raise HTTPException(400, "Only failed tasks can be retried")

    # Re-read originals from storage and re-run
    storage = _storage()
    images = db.query(Image).filter(
        Image.clothing_item_id == item_id,
        Image.image_type.in_(["ORIGINAL_FRONT", "ORIGINAL_BACK"]),
    ).all()

    front_bytes = None
    back_bytes = None
    for img in images:
        data = await storage.download(img.storage_path)
        if img.image_type == "ORIGINAL_FRONT":
            front_bytes = data
        else:
            back_bytes = data

    if not front_bytes:
        raise HTTPException(400, "Original front image not found, please re-upload")

    _, task = await run_pipeline(
        db, storage, item.user_id,
        front_bytes, back_bytes, item.name, item.description,
    )
    return ClothingItemCreateResponse(
        id=item.id, processingTaskId=task.id,
        status=task.status, estimatedTime=30,
    )


# ---- GET /clothing-items/:id/angle-views ----

@router.get("/{item_id}/angle-views", response_model=AngleViewsResponse)
def get_angle_views(item_id: UUID, db: Session = Depends(get_db)):
    images = (
        db.query(Image)
        .filter(Image.clothing_item_id == item_id, Image.image_type == "ANGLE_VIEW")
        .order_by(Image.angle)
        .all()
    )
    storage = _storage()
    views = {img.angle: storage.get_url(img.storage_path) for img in images if img.angle is not None}
    return AngleViewsResponse(angleViews=views)


# ---- GET /clothing-items/:id/model ----

@router.get("/{item_id}/model")
async def download_model(item_id: UUID, db: Session = Depends(get_db)):
    model = db.query(Model3D).filter(Model3D.clothing_item_id == item_id).first()
    if not model:
        raise HTTPException(404, "3D model not found")

    storage = _storage()
    data = await storage.download(model.storage_path)

    from fastapi.responses import Response
    return Response(
        content=data,
        media_type="model/gltf-binary",
        headers={"Content-Disposition": f"attachment; filename={item_id}.glb"},
    )


# ---- helpers ----

def _build_image_set(images: list[Image], storage: StorageService) -> ImageSetResponse:
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


def _progress_to_steps(progress: int, status: str) -> dict[str, str]:
    if status == "FAILED":
        return {"upload": "completed", "backgroundRemoval": "failed",
                "modelGeneration": "pending", "angleRendering": "pending"}

    def _s(threshold: int) -> str:
        if progress >= threshold + 20:
            return "completed"
        if progress >= threshold:
            return "processing"
        return "pending"

    return {
        "upload": "completed" if progress >= 5 else "processing",
        "backgroundRemoval": _s(15),
        "modelGeneration": _s(30),
        "angleRendering": _s(70),
    }
