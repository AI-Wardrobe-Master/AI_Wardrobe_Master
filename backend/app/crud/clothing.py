"""
Clothing CRUD - Module 2: final_tags update, search
"""
from datetime import datetime, timezone
from typing import List, Optional, Tuple
from uuid import UUID

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.models.clothing_item import ClothingItem, Image, Model3D
from app.models.creator import CardPack, CardPackItem
from app.models.wardrobe import WardrobeItem
from app.schemas.clothing_item import Tag
from app.services.blob_service import BlobService


def get(db: Session, item_id: UUID, user_id: UUID) -> Optional[ClothingItem]:
    return (
        db.query(ClothingItem)
        .filter(
            ClothingItem.id == item_id,
            ClothingItem.user_id == user_id,
            ClothingItem.deleted_at.is_(None),
        )
        .first()
    )


def update_final_tags(
    db: Session, item_id: UUID, user_id: UUID, final_tags: List[dict], is_confirmed: bool
) -> Optional[ClothingItem]:
    """Update final_tags (user confirmation/correction). predicted_tags remain immutable."""
    item = get(db, item_id, user_id)
    if not item:
        return None
    item.final_tags = [
        t if isinstance(t, dict) else {"key": t.key, "value": t.value}
        for t in final_tags
    ]
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
    category: Optional[str] = None,
    material: Optional[str] = None,
    style: Optional[str] = None,
    catalog_visibility: Optional[str] = None,
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
    if category is not None:
        item.category = category
    if material is not None:
        item.material = material
    if style is not None:
        item.style = style
    if catalog_visibility is not None:
        item.catalog_visibility = catalog_visibility
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
    q = db.query(ClothingItem).filter(
        ClothingItem.user_id == user_id,
        ClothingItem.deleted_at.is_(None),
    )

    if source:
        q = q.filter(ClothingItem.source == source)

    if query:
        q = q.filter(
            or_(
                ClothingItem.name.ilike(f"%{query}%"),
                ClothingItem.description.ilike(f"%{query}%"),
                ClothingItem.category.ilike(f"%{query}%"),
                ClothingItem.material.ilike(f"%{query}%"),
                ClothingItem.style.ilike(f"%{query}%"),
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
        for key_tags in by_key.values():
            or_conds = [ClothingItem.final_tags.contains([t]) for t in key_tags]
            q = q.filter(or_(*or_conds))

    total = q.count()
    offset = (page - 1) * limit
    items = q.offset(offset).limit(limit).all()
    return items, total


def create(
    db: Session,
    *,
    item_id: UUID,
    user_id: UUID,
    name: Optional[str] = None,
    description: Optional[str] = None,
    source: str = "OWNED",
    catalog_visibility: str = "PRIVATE",
) -> ClothingItem:
    item = ClothingItem(
        id=item_id,
        user_id=user_id,
        source=source,
        catalog_visibility=catalog_visibility,
        predicted_tags=[],
        final_tags=[],
        is_confirmed=False,
        custom_tags=[],
        name=name,
        description=description,
    )
    db.add(item)
    db.flush()
    return item


def list_published_by_user(
    db: Session,
    *,
    user_id: UUID,
    page: int = 1,
    limit: int = 20,
) -> Tuple[List[ClothingItem], int]:
    q = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.user_id == user_id,
            ClothingItem.catalog_visibility.in_(("PACK_ONLY", "PUBLIC")),
            ClothingItem.deleted_at.is_(None),
        )
        .order_by(ClothingItem.created_at.desc())
    )
    total = q.count()
    items = q.offset((page - 1) * limit).limit(limit).all()
    return items, total


def list_popular(
    db: Session,
    *,
    limit: int = 10,
) -> List[ClothingItem]:
    return (
        db.query(ClothingItem)
        .filter(
            ClothingItem.catalog_visibility.in_(("PACK_ONLY", "PUBLIC")),
            ClothingItem.deleted_at.is_(None),
        )
        .order_by(ClothingItem.view_count.desc(), ClothingItem.created_at.desc())
        .limit(limit)
        .all()
    )


def list_with_tag_filter(
    db: Session,
    user_id: UUID,
    *,
    source: Optional[str] = None,
    tag_key: Optional[str] = None,
    tag_value: Optional[str] = None,
    search: Optional[str] = None,
    wardrobe_id: Optional[UUID] = None,
    page: int = 1,
    limit: int = 20,
) -> Tuple[List[ClothingItem], int]:
    """GET /clothing-items with tagKey, tagValue, search filters"""
    q = db.query(ClothingItem).filter(
        ClothingItem.user_id == user_id,
        ClothingItem.deleted_at.is_(None),
    )

    if source:
        q = q.filter(ClothingItem.source == source)
    if wardrobe_id is not None:
        q = q.join(
            WardrobeItem,
            WardrobeItem.clothing_item_id == ClothingItem.id,
        ).filter(WardrobeItem.wardrobe_id == wardrobe_id)
    if tag_key and tag_value:
        q = q.filter(
            ClothingItem.final_tags.contains([{"key": tag_key, "value": tag_value}])
        )
    if search:
        q = q.filter(
            or_(
                ClothingItem.name.ilike(f"%{search}%"),
                ClothingItem.description.ilike(f"%{search}%"),
                ClothingItem.category.ilike(f"%{search}%"),
                ClothingItem.material.ilike(f"%{search}%"),
                ClothingItem.style.ilike(f"%{search}%"),
                func.array_to_string(ClothingItem.custom_tags, " ").ilike(f"%{search}%"),
            )
        )

    total = q.count()
    offset = (page - 1) * limit
    items = q.offset(offset).limit(limit).all()
    return items, total


def delete_with_lifecycle(
    db: Session,
    *,
    item_id: UUID,
    user_id: UUID,
    blob_service: BlobService,
) -> str | None:
    """Runs the 3-tier delete. Returns 'HARD_DELETED', 'TOMBSTONED', or None (not found)."""
    item = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.id == item_id,
            ClothingItem.user_id == user_id,
            ClothingItem.deleted_at.is_(None),
        )
        .with_for_update()
        .first()
    )
    if item is None:
        return None

    # Lock any PUBLISHED packs that reference this item. This serializes with
    # concurrent `POST /imports/card-pack` handlers (which FOR UPDATE the pack
    # row before snapshotting its items). Without this, an importer reading
    # the pack's items could race our delete and snapshot a canonical that is
    # about to be dropped or tombstoned. See spec §4.7 "Concurrency".
    published_packs = (
        db.query(CardPack)
        .join(CardPackItem, CardPackItem.card_pack_id == CardPack.id)
        .filter(
            CardPackItem.clothing_item_id == item.id,
            CardPack.status == "PUBLISHED",
        )
        .with_for_update()
        .all()
    )
    in_published_pack = bool(published_packs)

    import_count = (
        db.query(ClothingItem)
        .filter(ClothingItem.imported_from_clothing_item_id == item.id)
        .count()
    )

    if not in_published_pack or import_count == 0:
        _hard_delete(db, item, blob_service)
        return "HARD_DELETED"
    else:
        _tombstone(db, item, blob_service)
        return "TOMBSTONED"


def _hard_delete(db: Session, item: ClothingItem, blob_service: BlobService) -> None:
    blob_hashes = [img.blob_hash for img in item.images if img.blob_hash]
    if item.model_3d and item.model_3d.blob_hash:
        blob_hashes.append(item.model_3d.blob_hash)

    db.query(WardrobeItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    db.query(CardPackItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    db.delete(item)
    db.flush()
    for h in blob_hashes:
        if h:
            blob_service.release(db, h)


def _tombstone(db: Session, item: ClothingItem, blob_service: BlobService) -> None:
    blob_hashes = [img.blob_hash for img in item.images if img.blob_hash]
    if item.model_3d and item.model_3d.blob_hash:
        blob_hashes.append(item.model_3d.blob_hash)

    db.query(WardrobeItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    db.query(CardPackItem).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)

    # Delete publisher-side images + model. Consumer IMPORTED copies have their own Image/Model3D rows.
    db.query(Image).filter_by(clothing_item_id=item.id).delete(synchronize_session=False)
    if item.model_3d:
        db.delete(item.model_3d)

    item.deleted_at = datetime.now(timezone.utc)
    db.flush()

    for h in blob_hashes:
        if h:
            blob_service.release(db, h)
