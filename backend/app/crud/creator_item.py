from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.creator import CreatorItem


def get_owned_creator_item(
    db: Session,
    *,
    item_id,
    creator_id,
    for_update: bool = False,
):
    query = db.query(CreatorItem).filter(
        CreatorItem.id == item_id,
        CreatorItem.creator_id == creator_id,
    )
    if for_update:
        query = query.with_for_update()
    return query.first()


def create_creator_item(
    db: Session,
    *,
    item_id,
    creator_id,
    name: str | None = None,
    description: str | None = None,
    catalog_visibility: str = "PACK_ONLY",
):
    item = CreatorItem(
        id=item_id,
        creator_id=creator_id,
        name=name,
        description=description,
        catalog_visibility=catalog_visibility,
        predicted_tags=[],
        final_tags=[],
        is_confirmed=False,
        processing_status="PENDING",
    )
    db.add(item)
    db.flush()
    return item


def update_creator_item(
    db: Session,
    item: CreatorItem,
    *,
    name: str | None = None,
    description: str | None = None,
    final_tags: list[dict] | None = None,
    custom_tags: list[str] | None = None,
    catalog_visibility: str | None = None,
):
    if name is not None:
        item.name = name
    if description is not None:
        item.description = description
    if final_tags is not None:
        item.final_tags = final_tags
        item.is_confirmed = True
    if custom_tags is not None:
        item.custom_tags = custom_tags
    if catalog_visibility is not None:
        item.catalog_visibility = catalog_visibility
    db.commit()
    db.refresh(item)
    return item


def delete_creator_item(db: Session, item: CreatorItem) -> None:
    db.delete(item)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Creator item delete conflicts with current database state",
        ) from exc


def list_public_creator_items_by_creator(
    db: Session,
    *,
    creator_id,
    page: int = 1,
    limit: int = 20,
):
    query = (
        db.query(CreatorItem)
        .filter(
            CreatorItem.creator_id == creator_id,
            CreatorItem.catalog_visibility.in_(("PACK_ONLY", "PUBLIC")),
        )
        .order_by(CreatorItem.created_at.desc())
    )
    total = query.count()
    items = query.offset((page - 1) * limit).limit(limit).all()
    return items, total
