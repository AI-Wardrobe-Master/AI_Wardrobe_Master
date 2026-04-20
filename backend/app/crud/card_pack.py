from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.crud import wardrobe as crud_wardrobe
from app.models.clothing_item import ClothingItem
from app.models.creator import CardPack, CardPackItem
from app.models.user import User
from app.models.wardrobe import Wardrobe


def get_owned_card_pack(
    db: Session,
    *,
    pack_id,
    creator_id,
    for_update: bool = False,
):
    query = db.query(CardPack).filter(
        CardPack.id == pack_id,
        CardPack.creator_id == creator_id,
    )
    if for_update:
        query = query.with_for_update()
    return query.first()


def get_public_card_pack(
    db: Session,
    *,
    pack_id: UUID | None = None,
    share_id: str | None = None,
):
    query = db.query(CardPack).filter(CardPack.status == "PUBLISHED")
    if pack_id is not None:
        query = query.filter(CardPack.id == pack_id)
    if share_id is not None:
        query = query.filter(CardPack.share_id == share_id)
    return query.first()


def list_public_card_packs(
    db: Session,
    *,
    search: str | None = None,
    page: int = 1,
    limit: int = 20,
):
    query = (
        db.query(CardPack)
        .join(User, User.id == CardPack.creator_id)
        .outerjoin(Wardrobe, Wardrobe.id == CardPack.wardrobe_id)
        .filter(CardPack.status == "PUBLISHED")
    )
    normalized_search = (search or "").strip()
    if normalized_search:
        pattern = f"%{normalized_search}%"
        query = query.filter(
            or_(
                CardPack.name.ilike(pattern),
                CardPack.description.ilike(pattern),
                User.uid.ilike(pattern),
                User.username.ilike(pattern),
                Wardrobe.wid.ilike(pattern),
            )
        )
    total = query.count()
    packs = (
        query.order_by(CardPack.published_at.desc(), CardPack.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    return packs, total


def list_creator_card_packs(
    db: Session,
    *,
    creator_id,
    include_unpublished: bool = False,
    page: int = 1,
    limit: int = 20,
):
    query = db.query(CardPack).filter(CardPack.creator_id == creator_id)
    if not include_unpublished:
        query = query.filter(CardPack.status == "PUBLISHED")
    total = query.count()
    packs = (
        query.order_by(CardPack.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    return packs, total


def count_published_card_packs_by_creator(db: Session, *, creator_id):
    return (
        db.query(CardPack)
        .filter(
            CardPack.creator_id == creator_id,
            CardPack.status == "PUBLISHED",
        )
        .count()
    )


def _load_creator_items(
    db: Session,
    *,
    creator_id,
    item_ids: list[UUID],
) -> list[ClothingItem]:
    if not item_ids:
        raise HTTPException(status_code=422, detail="itemIds must not be empty")
    if len(item_ids) != len(set(item_ids)):
        raise HTTPException(status_code=409, detail="itemIds must be unique")

    items = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.user_id == creator_id,
            ClothingItem.id.in_(item_ids),
            ClothingItem.deleted_at.is_(None),
        )
        .all()
    )
    items_by_id = {item.id: item for item in items}
    ordered_items: list[ClothingItem] = []
    missing_ids: list[UUID] = []
    for item_id in item_ids:
        item = items_by_id.get(item_id)
        if item is None:
            missing_ids.append(item_id)
            continue
        ordered_items.append(item)
    if missing_ids:
        raise HTTPException(status_code=404, detail="Clothing item not found")
    return ordered_items


def _sync_pack_items(
    db: Session,
    *,
    pack: CardPack,
    clothing_items: list[ClothingItem],
) -> CardPack:
    now = datetime.now(timezone.utc)
    pack.items.clear()
    _flush_or_raise_conflict(
        db,
        detail="Card pack items conflict with current database state",
    )
    if hasattr(db, "pack_items"):
        db.pack_items = [
            item for item in db.pack_items if item.card_pack_id != pack.id
        ]
    for sort_order, clothing_item in enumerate(clothing_items):
        pack_item = CardPackItem(
            id=uuid4(),
            card_pack_id=pack.id,
            clothing_item_id=clothing_item.id,
            sort_order=sort_order,
            created_at=now,
        )
        pack_item.clothing_item = clothing_item
        pack.items.append(pack_item)
        db.add(pack_item)
    return pack


def _flush_or_raise_conflict(db: Session, *, detail: str) -> None:
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail=detail) from exc


def _commit_or_raise_conflict(db: Session, *, detail: str) -> None:
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail=detail) from exc


def _lock_pack_clothing_items(db: Session, *, pack: CardPack) -> dict[UUID, ClothingItem]:
    clothing_item_ids = [pack_item.clothing_item_id for pack_item in pack.items]
    if not clothing_item_ids:
        return {}
    locked_items = (
        db.query(ClothingItem)
        .filter(ClothingItem.id.in_(clothing_item_ids))
        .with_for_update()
        .all()
    )
    return {item.id: item for item in locked_items}


def _dedupe_strings(values: list[str | None]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for value in values:
        if value is None:
            continue
        normalized = value.strip()
        if not normalized:
            continue
        key = normalized.lower()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(normalized)
    return ordered


def _build_pack_share_tags(pack: CardPack, creator: User | None) -> list[str]:
    return _dedupe_strings(
        [
            pack.name,
            creator.uid if creator else None,
            creator.username if creator else None,
            pack.share_id,
            f"pack:{pack.id}",
        ]
    )


def _ensure_pack_share_wardrobe(db: Session, *, pack: CardPack) -> Wardrobe:
    creator = db.get(User, pack.creator_id)
    main_wardrobe = crud_wardrobe.get_main_wardrobe(db, pack.creator_id)
    if main_wardrobe is None:
        main_wardrobe = Wardrobe(
            id=uuid4(),
            wid=crud_wardrobe._generate_wid(db),
            user_id=pack.creator_id,
            name="My Wardrobe",
            kind="MAIN",
            type="REGULAR",
            source="MANUAL",
            description="Default main wardrobe",
            auto_tags=[],
            manual_tags=[],
            is_public=False,
        )
        db.add(main_wardrobe)
        db.flush()
    wardrobe = db.get(Wardrobe, pack.wardrobe_id) if pack.wardrobe_id else None
    if wardrobe is None:
        wardrobe = Wardrobe(
            id=uuid4(),
            wid=crud_wardrobe._generate_wid(db),
            user_id=pack.creator_id,
            parent_wardrobe_id=main_wardrobe.id,
            name=pack.name,
            kind="SUB",
            type="VIRTUAL",
            source="CARD_PACK",
            description=pack.description,
            cover_image_url=(
                f"/files/card-packs/{pack.id}/cover"
                if pack.cover_image_blob_hash
                else None
            ),
            auto_tags=_build_pack_share_tags(pack, creator),
            manual_tags=[],
            is_public=True,
        )
        db.add(wardrobe)
        db.flush()
        pack.wardrobe_id = wardrobe.id
    else:
        wardrobe.user_id = pack.creator_id
        wardrobe.parent_wardrobe_id = wardrobe.parent_wardrobe_id or main_wardrobe.id
        wardrobe.name = pack.name
        wardrobe.kind = "SUB"
        wardrobe.type = "VIRTUAL"
        wardrobe.source = "CARD_PACK"
        wardrobe.description = pack.description
        wardrobe.cover_image_url = (
            f"/files/card-packs/{pack.id}/cover" if pack.cover_image_blob_hash else None
        )
        wardrobe.auto_tags = _build_pack_share_tags(pack, creator)
        wardrobe.is_public = True
    return wardrobe


def create_card_pack(
    db: Session,
    *,
    creator_id,
    name: str,
    description: str | None = None,
    pack_type: str = "CLOTHING_COLLECTION",
    cover_image_blob_hash: str | None = None,
    item_ids: list[UUID],
):
    now = datetime.now(timezone.utc)
    items = _load_creator_items(db, creator_id=creator_id, item_ids=item_ids)
    pack = CardPack(
        id=uuid4(),
        creator_id=creator_id,
        name=name,
        description=description,
        pack_type=pack_type,
        status="DRAFT",
        cover_image_blob_hash=cover_image_blob_hash,
        import_count=0,
        created_at=now,
        updated_at=now,
    )
    db.add(pack)
    _flush_or_raise_conflict(
        db,
        detail="Card pack conflicts with current database state",
    )
    _sync_pack_items(db, pack=pack, clothing_items=items)
    _commit_or_raise_conflict(
        db,
        detail="Card pack conflicts with current database state",
    )
    db.refresh(pack)
    return pack


def update_card_pack(
    db: Session,
    pack: CardPack,
    *,
    name: str | None = None,
    description: str | None = None,
    item_ids: list[UUID] | None = None,
    cover_image_blob_hash: str | None = None,
):
    if pack.status == "ARCHIVED":
        raise HTTPException(status_code=409, detail="Archived packs cannot be updated")

    now = datetime.now(timezone.utc)
    if name is not None:
        pack.name = name
    if description is not None:
        pack.description = description
    if cover_image_blob_hash is not None:
        pack.cover_image_blob_hash = cover_image_blob_hash
    if item_ids is not None:
        if pack.status != "DRAFT":
            raise HTTPException(
                status_code=409,
                detail="Published packs cannot change items",
            )
        items = _load_creator_items(
            db,
            creator_id=pack.creator_id,
            item_ids=item_ids,
        )
        _sync_pack_items(db, pack=pack, clothing_items=items)
    if pack.status == "PUBLISHED" or pack.wardrobe_id is not None:
        _ensure_pack_share_wardrobe(db, pack=pack)
    pack.updated_at = now
    _commit_or_raise_conflict(
        db,
        detail="Card pack update conflicts with current database state",
    )
    db.refresh(pack)
    return pack


def publish_card_pack(db: Session, pack: CardPack):
    if pack.status != "DRAFT":
        raise HTTPException(status_code=409, detail="Pack cannot be published")
    if not pack.items:
        raise HTTPException(status_code=409, detail="Pack must contain at least one item")

    from app.services.processing_task_service import get_latest_task

    locked_items = _lock_pack_clothing_items(db, pack=pack)
    for pack_item in pack.items:
        clothing_item = locked_items.get(pack_item.clothing_item_id) or pack_item.clothing_item
        if clothing_item is None:
            raise HTTPException(status_code=422, detail="Pack item data is corrupted")
        if clothing_item.deleted_at is not None:
            raise HTTPException(
                status_code=409,
                detail="Pack contains deleted clothing items",
            )
        latest_task = get_latest_task(db, clothing_item.id)
        if latest_task is not None and latest_task.status != "COMPLETED":
            raise HTTPException(
                status_code=409,
                detail="All pack items must be processed before publishing",
            )

    now = datetime.now(timezone.utc)
    if not pack.share_id:
        pack.share_id = uuid4().hex
    pack.status = "PUBLISHED"
    pack.published_at = now
    _ensure_pack_share_wardrobe(db, pack=pack)
    pack.updated_at = now
    _commit_or_raise_conflict(
        db,
        detail="Card pack publish conflicts with current database state",
    )
    db.refresh(pack)
    return pack


def archive_card_pack(db: Session, pack: CardPack):
    if pack.status != "PUBLISHED":
        raise HTTPException(status_code=409, detail="Pack cannot be archived")
    now = datetime.now(timezone.utc)
    pack.status = "ARCHIVED"
    pack.archived_at = now
    if pack.wardrobe_id:
        wardrobe = db.get(Wardrobe, pack.wardrobe_id)
        if wardrobe is not None:
            wardrobe.is_public = False
    pack.updated_at = now
    _commit_or_raise_conflict(
        db,
        detail="Card pack archive conflicts with current database state",
    )
    db.refresh(pack)
    return pack


def delete_card_pack(db: Session, pack: CardPack) -> None:
    if pack.wardrobe_id:
        linked_wardrobe = db.get(Wardrobe, pack.wardrobe_id)
        if linked_wardrobe is not None:
            db.delete(linked_wardrobe)
    db.delete(pack)
    _commit_or_raise_conflict(
        db,
        detail="Card pack delete conflicts with current database state",
    )


def has_published_pack_reference(db: Session, *, clothing_item_id) -> bool:
    for pack_item in (
        db.query(CardPackItem)
        .filter(CardPackItem.clothing_item_id == clothing_item_id)
        .all()
    ):
        pack = pack_item.card_pack or db.get(CardPack, pack_item.card_pack_id)
        if pack is not None and pack.status == "PUBLISHED":
            return True
    return False


def list_popular_card_packs(
    db: Session,
    *,
    limit: int = 10,
) -> list[CardPack]:
    return (
        db.query(CardPack)
        .filter(CardPack.status == "PUBLISHED")
        .order_by(CardPack.view_count.desc(), CardPack.created_at.desc())
        .limit(limit)
        .all()
    )
