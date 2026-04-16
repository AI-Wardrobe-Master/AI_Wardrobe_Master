from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.crud import outfit_preview as crud_outfit_preview
from app.db.session import get_db
from app.schemas.creator import Pagination
from app.schemas.outfit_preview import (
    OutfitDetail,
    OutfitItemSummary,
    OutfitPreviewSaveResponse,
    OutfitPreviewTaskCreateResponse,
    OutfitPreviewTaskCreateResponseData,
    OutfitPreviewTaskDetail,
    OutfitPreviewTaskItemSummary,
    OutfitPreviewTaskListData,
    OutfitPreviewTaskListResponse,
    OutfitPreviewTaskListItem,
)
from app.services.outfit_preview_service import (
    create_preview_task,
    enqueue_preview_generation,
    save_outfit_from_preview_task,
)

router = APIRouter(prefix="/outfit-preview-tasks", tags=["outfit-preview"])
ALLOWED_STATUSES = {"PENDING", "PROCESSING", "COMPLETED", "FAILED"}


@router.post("", response_model=OutfitPreviewTaskCreateResponse, status_code=202)
async def create_outfit_preview_task_route(
    person_image: UploadFile = File(...),
    clothing_item_ids: list[UUID] = Form(..., alias="clothing_item_ids[]"),
    person_view_type: str = Form(...),
    garment_categories: list[str] = Form(..., alias="garment_categories[]"),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    task = await create_preview_task(
        db,
        user_id=user_id,
        person_image=person_image,
        person_view_type=person_view_type,
        clothing_item_ids=clothing_item_ids,
        garment_categories=garment_categories,
    )
    try:
        enqueue_preview_generation(task.id)
    except Exception as exc:
        crud_outfit_preview.mark_outfit_preview_failed(
            db,
            task=task,
            error_code="DISPATCH_FAILED",
            error_message=str(exc),
        )
        raise HTTPException(status_code=503, detail=f"Task dispatch failed: {exc}") from exc

    return OutfitPreviewTaskCreateResponse(
        data=OutfitPreviewTaskCreateResponseData(
            id=task.id,
            status=task.status,
            clothingItemIds=[item.clothing_item_id for item in task.items],
            personViewType=task.person_view_type,
            garmentCategories=[item.garment_category for item in task.items],
            createdAt=task.created_at,
        )
    )


@router.get("/{task_id}", response_model=OutfitPreviewTaskDetail)
def get_outfit_preview_task(
    task_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    task = crud_outfit_preview.get_owned_outfit_preview_task(
        db,
        task_id=task_id,
        user_id=user_id,
    )
    if task is None:
        raise HTTPException(status_code=404, detail="Preview task not found")
    return _to_task_detail(task)


@router.get("", response_model=OutfitPreviewTaskListResponse)
def list_outfit_preview_tasks(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
    status: str | None = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
):
    if status is not None:
        normalized = status.upper()
        if normalized not in ALLOWED_STATUSES:
            raise HTTPException(status_code=422, detail="Invalid preview task status")
    else:
        normalized = None
    tasks, total = crud_outfit_preview.list_owned_outfit_preview_tasks(
        db,
        user_id=user_id,
        status=normalized,
        page=page,
        limit=limit,
    )
    return OutfitPreviewTaskListResponse(
        data=OutfitPreviewTaskListData(
            items=[_to_task_list_item(task) for task in tasks],
            pagination=Pagination.build(page=page, limit=limit, total=total),
        )
    )


@router.post("/{task_id}/save", response_model=OutfitPreviewSaveResponse, status_code=201)
def save_outfit_from_preview_task_route(
    task_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    task = crud_outfit_preview.get_owned_outfit_preview_task(
        db,
        task_id=task_id,
        user_id=user_id,
    )
    if task is None:
        raise HTTPException(status_code=404, detail="Preview task not found")
    outfit = save_outfit_from_preview_task(db, task=task)
    return OutfitPreviewSaveResponse(data=_to_outfit_detail(outfit))


def _to_task_detail(task) -> OutfitPreviewTaskDetail:
    return OutfitPreviewTaskDetail(
        id=task.id,
        status=task.status,
        clothingItemIds=[item.clothing_item_id for item in task.items],
        personViewType=task.person_view_type,
        garmentCategories=[item.garment_category for item in task.items],
        previewImageUrl=f"/files/outfit-preview-tasks/{task.id}/preview"
        if task.preview_image_blob_hash
        else None,
        errorCode=task.error_code,
        errorMessage=task.error_message,
        providerName=task.provider_name,
        providerModel=task.provider_model,
        createdAt=task.created_at,
        startedAt=task.started_at,
        completedAt=task.completed_at,
        items=[
            OutfitPreviewTaskItemSummary(
                clothingItemId=item.clothing_item_id,
                garmentCategory=item.garment_category,
                sortOrder=item.sort_order,
            )
            for item in task.items
        ],
    )


def _to_task_list_item(task) -> OutfitPreviewTaskListItem:
    return OutfitPreviewTaskListItem.model_validate(_to_task_detail(task).model_dump(by_alias=True))


def _to_outfit_detail(outfit) -> OutfitDetail:
    return OutfitDetail(
        id=outfit.id,
        userId=outfit.user_id,
        previewTaskId=outfit.preview_task_id,
        name=outfit.name,
        previewImageUrl=f"/files/outfits/{outfit.id}/preview",
        clothingItemIds=[item.clothing_item_id for item in outfit.items],
        createdAt=outfit.created_at,
        updatedAt=outfit.updated_at,
        items=[
            OutfitItemSummary(
                id=item.id,
                clothingItemId=item.clothing_item_id,
                createdAt=item.created_at,
            )
            for item in outfit.items
        ],
    )
