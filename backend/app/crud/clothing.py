"""
Clothing CRUD - Module 2: final_tags update, search
"""
from typing import Optional, List, Tuple
from uuid import UUID
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from app.models.clothing_item import ClothingItem
from app.schemas.clothing_item import Tag


def get(db: Session, item_id: UUID, user_id: UUID) -> Optional[ClothingItem]:
    return (
        db.query(ClothingItem)
        .filter(ClothingItem.id == item_id, ClothingItem.user_id == user_id)
        .first()
    )


def update_final_tags(
    db: Session, item_id: UUID, user_id: UUID, final_tags: List[dict], is_confirmed: bool
) -> Optional[ClothingItem]:
    """Update final_tags (user confirmation/correction). predicted_tags remain immutable."""
    item = get(db, item_id, user_id)
    if not item:
        return None
    item.final_tags = [t if isinstance(t, dict) else {"key": t.key, "value": t.value} for t in final_tags]
    item.is_confirmed = is_confirmed
    db.commit()
    db.refresh(item)
    return item


def update(
    db: Session,
    item_id: UUID,
    user_id: UUID,
    *,
    name: Optional[str] = None,
    description: Optional[str] = None,
    final_tags: Optional[List[Tag]] = None,
    is_confirmed: Optional[bool] = None,
    custom_tags: Optional[List[str]] = None,
) -> Optional[ClothingItem]:
    """Full update for PATCH /clothing-items/:id"""
    item = get(db, item_id, user_id)
    if not item:
        return None
    if name is not None:
        item.name = name
    if description is not None:
        item.description = description
    if final_tags is not None:
        item.final_tags = [{"key": t.key, "value": t.value} for t in final_tags]
    if is_confirmed is not None:
        item.is_confirmed = is_confirmed
    if custom_tags is not None:
        item.custom_tags = custom_tags
    db.commit()
    db.refresh(item)
    return item


def search_by_final_tags(
    db: Session,
    user_id: UUID,
    *,
    tags: Optional[List[dict]] = None,
    source: Optional[str] = None,
    query: Optional[str] = None,
    page: int = 1,
    limit: int = 20,
) -> Tuple[List[ClothingItem], int]:
    """
    Search using final_tags only (not predicted_tags).
    Multiple tags with same key = OR; different keys = AND.
    """
    q = db.query(ClothingItem).filter(ClothingItem.user_id == user_id)

    if source:
        q = q.filter(ClothingItem.source == source)

    if query:
        q = q.filter(
            or_(
                ClothingItem.name.ilike(f"%{query}%"),
                ClothingItem.description.ilike(f"%{query}%"),
                func.array_to_string(ClothingItem.custom_tags, " ").ilike(f"%{query}%"),
            )
        )

    if tags:
        from collections import defaultdict
        by_key = defaultdict(list)
        for tag in tags:
            key = tag.get("key")
            value = tag.get("value")
            if key and value:
                by_key[key].append({"key": key, "value": value})
        for key, key_tags in by_key.items():
            or_conds = [
                ClothingItem.final_tags.contains([t]) for t in key_tags
            ]
            q = q.filter(or_(*or_conds))

    total = q.count()
    offset = (page - 1) * limit
    items = q.offset(offset).limit(limit).all()
    return items, total


def list_with_tag_filter(
    db: Session,
    user_id: UUID,
    *,
    source: Optional[str] = None,
    tag_key: Optional[str] = None,
    tag_value: Optional[str] = None,
    search: Optional[str] = None,
    page: int = 1,
    limit: int = 20,
) -> Tuple[List[ClothingItem], int]:
    """GET /clothing-items with tagKey, tagValue, search filters"""
    q = db.query(ClothingItem).filter(ClothingItem.user_id == user_id)

    if source:
        q = q.filter(ClothingItem.source == source)
    if tag_key and tag_value:
        q = q.filter(
            ClothingItem.final_tags.contains([{"key": tag_key, "value": tag_value}])
        )
    if search:
        q = q.filter(
            or_(
                ClothingItem.name.ilike(f"%{search}%"),
                ClothingItem.description.ilike(f"%{search}%"),
                func.array_to_string(ClothingItem.custom_tags, " ").ilike(f"%{search}%"),
            )
        )

    total = q.count()
    offset = (page - 1) * limit
    items = q.offset(offset).limit(limit).all()
    return items, total
