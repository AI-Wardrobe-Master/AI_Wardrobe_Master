"""
Clothing Items API - PATCH, GET list, POST search
Module 2.4
"""
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.db.session import get_db
from app.crud import clothing as crud_clothing
from app.schemas.clothing_item import ClothingItemUpdate
from app.schemas.search import SearchRequest
from app.services.search_service import SearchService

router = APIRouter()


def _item_to_response(item) -> dict:
    """将 ClothingItem 转为 API 响应格式"""
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


@router.patch("/{item_id}")
def update_clothing_item(
    item_id: UUID,
    body: ClothingItemUpdate,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """
    PATCH /clothing-items/:id
    支持 tag 确认与编辑：finalTags, isConfirmed
    predictedTags 不可修改。
    """
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


@router.get("/")
def list_clothing_items(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
    source: Optional[str] = Query(None),
    tag_key: Optional[str] = Query(None),
    tag_value: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
):
    """
    GET /clothing-items
    支持 source, tagKey, tagValue, search 过滤。搜索使用 finalTags。
    """
    items, total = crud_clothing.list_with_tag_filter(
        db, user_id,
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
    """
    POST /clothing-items/search
    使用 finalTags 搜索，支持 query、filters.tags、filters.source
    """
    filters = body.filters.model_dump(exclude_none=True) if body.filters else None
    items, total = SearchService().search(
        db, user_id,
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
