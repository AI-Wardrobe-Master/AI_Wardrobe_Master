"""Module 3: Wardrobe CRUD. Delete wardrobe only removes junction rows, not clothing_items."""
import secrets
from datetime import datetime
from typing import List, Optional, Tuple
from uuid import UUID

from sqlalchemy import case, func, or_
from sqlalchemy.orm import Session

from app.models.clothing_item import ClothingItem
from app.models.user import User
from app.models.wardrobe import Wardrobe, WardrobeItem


def _generate_wid(db: Session) -> str:
    while True:
        candidate = f"WRD-{secrets.token_hex(4).upper()}"
        existing = db.query(Wardrobe).filter(Wardrobe.wid == candidate).first()
        if existing is None:
            return candidate


def _tag_strings_for_item(item: ClothingItem) -> list[str]:
    tags: list[str] = []
    for raw in item.final_tags or []:
        if isinstance(raw, dict):
            value = raw.get("value")
            key = raw.get("key")
            if value:
                tags.append(str(value).strip())
            elif key:
                tags.append(str(key).strip())
        elif raw:
            tags.append(str(raw).strip())
    for raw in item.custom_tags or []:
        if raw:
            tags.append(str(raw).strip())
    return [tag for tag in tags if tag]


def _dedupe_tags(tags: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for tag in tags:
        normalized = tag.strip()
        if not normalized:
            continue
        key = normalized.lower()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(normalized)
    return ordered


def _default_export_name() -> str:
    return f"Styled Look {datetime.now().strftime('%Y-%m-%d %H:%M')}"


def get_main_wardrobe(db: Session, user_id: UUID) -> Wardrobe | None:
    return (
        db.query(Wardrobe)
        .filter(Wardrobe.user_id == user_id, Wardrobe.kind == "MAIN")
        .first()
    )


def ensure_main_wardrobe(db: Session, user_id: UUID) -> Wardrobe:
    wardrobe = get_main_wardrobe(db, user_id)
    if wardrobe is not None:
        return wardrobe

    wardrobe = Wardrobe(
        wid=_generate_wid(db),
        user_id=user_id,
        name="My Wardrobe",
        kind="MAIN",
        type="REGULAR",
        source="MANUAL",
        description="Default main wardrobe",
        auto_tags=[],
        manual_tags=[],
        is_public=False,
    )
    db.add(wardrobe)
    db.commit()
    db.refresh(wardrobe)
    return wardrobe


def list_wardrobes(db: Session, user_id: UUID) -> List[Wardrobe]:
    ensure_main_wardrobe(db, user_id)
    return (
        db.query(Wardrobe)
        .filter(Wardrobe.user_id == user_id)
        .order_by(
            case((Wardrobe.kind == "MAIN", 0), else_=1),
            Wardrobe.created_at,
        )
        .all()
    )


def list_public_wardrobes(
    db: Session,
    *,
    search: str | None = None,
    page: int = 1,
    limit: int = 20,
) -> tuple[List[Wardrobe], int]:
    query = (
        db.query(Wardrobe)
        .join(User, User.id == Wardrobe.user_id)
        .filter(Wardrobe.is_public.is_(True))
    )
    normalized_search = (search or "").strip()
    if normalized_search:
        pattern = f"%{normalized_search}%"
        query = query.filter(
            or_(
                Wardrobe.wid.ilike(pattern),
                Wardrobe.name.ilike(pattern),
                Wardrobe.description.ilike(pattern),
                User.uid.ilike(pattern),
                User.username.ilike(pattern),
                func.array_to_string(Wardrobe.auto_tags, " ").ilike(pattern),
                func.array_to_string(Wardrobe.manual_tags, " ").ilike(pattern),
            )
        )
    total = query.count()
    wardrobes = (
        query.order_by(Wardrobe.updated_at.desc(), Wardrobe.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    return wardrobes, total


def get_wardrobe(db: Session, wardrobe_id: UUID, user_id: UUID) -> Optional[Wardrobe]:
    return (
        db.query(Wardrobe)
        .filter(Wardrobe.id == wardrobe_id, Wardrobe.user_id == user_id)
        .first()
    )


def get_wardrobe_by_wid(
    db: Session,
    wid: str,
    *,
    viewer_user_id: UUID | None = None,
) -> Wardrobe | None:
    normalized_wid = wid.strip().upper()
    query = db.query(Wardrobe).filter(func.upper(Wardrobe.wid) == normalized_wid)
    if viewer_user_id is not None:
        query = query.filter(
            or_(Wardrobe.user_id == viewer_user_id, Wardrobe.is_public.is_(True))
        )
    else:
        query = query.filter(Wardrobe.is_public.is_(True))
    return query.first()


def create_wardrobe(
    db: Session,
    user_id: UUID,
    *,
    name: str,
    type: str = "REGULAR",
    description: Optional[str] = None,
    cover_image_url: str | None = None,
    manual_tags: list[str] | None = None,
    is_public: bool = False,
    kind: str = "SUB",
    source: str = "MANUAL",
    parent_wardrobe_id: UUID | None = None,
    outfit_id: UUID | None = None,
    auto_tags: list[str] | None = None,
) -> Wardrobe:
    if kind == "MAIN":
        existing_main = get_main_wardrobe(db, user_id)
        if existing_main is not None:
            return existing_main

    w = Wardrobe(
        wid=_generate_wid(db),
        user_id=user_id,
        name=name,
        kind=kind,
        type=type,
        source=source,
        description=description,
        cover_image_url=cover_image_url,
        auto_tags=_dedupe_tags(auto_tags or []),
        manual_tags=_dedupe_tags(manual_tags or []),
        is_public=is_public,
        parent_wardrobe_id=parent_wardrobe_id,
        outfit_id=outfit_id,
    )
    db.add(w)
    db.commit()
    db.refresh(w)
    return w


def update_wardrobe(
    db: Session,
    wardrobe_id: UUID,
    user_id: UUID,
    *,
    name: Optional[str] = None,
    description: Optional[str] = None,
    cover_image_url: str | None = None,
    manual_tags: list[str] | None = None,
    is_public: bool | None = None,
) -> Optional[Wardrobe]:
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        return None
    if name is not None:
        w.name = name
    if description is not None:
        w.description = description
    if cover_image_url is not None:
        w.cover_image_url = cover_image_url
    if manual_tags is not None:
        w.manual_tags = _dedupe_tags(manual_tags)
    if is_public is not None:
        w.is_public = is_public
    db.commit()
    db.refresh(w)
    return w


def delete_wardrobe(db: Session, wardrobe_id: UUID, user_id: UUID) -> bool:
    """Delete wardrobe and its wardrobe_items only. Clothing items are untouched."""
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w or w.kind == "MAIN":
        return False
    db.delete(w)
    db.commit()
    return True


def get_item_count(db: Session, wardrobe_id: UUID) -> int:
    return db.query(func.count(WardrobeItem.id)).filter(WardrobeItem.wardrobe_id == wardrobe_id).scalar() or 0


def count_items_by_wardrobe_ids(
    db: Session, wardrobe_ids: list[UUID],
) -> dict[UUID, int]:
    """Batch fetch item counts for multiple wardrobes. Returns {id: count}."""
    if not wardrobe_ids:
        return {}
    rows = (
        db.query(WardrobeItem.wardrobe_id, func.count(WardrobeItem.id))
        .filter(WardrobeItem.wardrobe_id.in_(wardrobe_ids))
        .group_by(WardrobeItem.wardrobe_id)
        .all()
    )
    return {wid: cnt for wid, cnt in rows}


def list_wardrobe_items(
    db: Session, wardrobe_id: UUID, user_id: UUID
) -> List[Tuple[WardrobeItem, ClothingItem]]:
    """Returns (WardrobeItem, ClothingItem) for each entry. Ensures wardrobe belongs to user and clothing exists."""
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        return []
    rows = (
        db.query(WardrobeItem, ClothingItem)
        .join(ClothingItem, WardrobeItem.clothing_item_id == ClothingItem.id)
        .filter(
            WardrobeItem.wardrobe_id == wardrobe_id,
            ClothingItem.user_id == user_id,
        )
        .order_by(WardrobeItem.display_order.nullslast(), WardrobeItem.added_at)
        .all()
    )
    return rows


def list_public_wardrobe_items(
    db: Session,
    wardrobe_id: UUID,
) -> List[Tuple[WardrobeItem, ClothingItem]]:
    return (
        db.query(WardrobeItem, ClothingItem)
        .join(Wardrobe, Wardrobe.id == WardrobeItem.wardrobe_id)
        .join(ClothingItem, WardrobeItem.clothing_item_id == ClothingItem.id)
        .filter(
            WardrobeItem.wardrobe_id == wardrobe_id,
            ClothingItem.user_id == Wardrobe.user_id,
        )
        .order_by(WardrobeItem.display_order.nullslast(), WardrobeItem.added_at)
        .all()
    )


def _link_item_to_wardrobe(
    db: Session,
    *,
    wardrobe_id: UUID,
    clothing_item_id: UUID,
) -> WardrobeItem:
    existing = (
        db.query(WardrobeItem)
        .filter(
            WardrobeItem.wardrobe_id == wardrobe_id,
            WardrobeItem.clothing_item_id == clothing_item_id,
        )
        .first()
    )
    if existing:
        return existing
    wi = WardrobeItem(wardrobe_id=wardrobe_id, clothing_item_id=clothing_item_id)
    db.add(wi)
    db.flush()
    return wi


def ensure_item_in_wardrobe(
    db: Session,
    *,
    user_id: UUID,
    wardrobe_id: UUID,
    clothing_item_id: UUID,
) -> Optional[WardrobeItem]:
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        return None
    clothing = db.query(ClothingItem).filter(
        ClothingItem.id == clothing_item_id, ClothingItem.user_id == user_id
    ).first()
    if not clothing:
        return None
    return _link_item_to_wardrobe(
        db,
        wardrobe_id=wardrobe_id,
        clothing_item_id=clothing_item_id,
    )


def add_item_to_wardrobe(
    db: Session, wardrobe_id: UUID, user_id: UUID, clothing_item_id: UUID
) -> Optional[WardrobeItem]:
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        return None
    clothing = db.query(ClothingItem).filter(
        ClothingItem.id == clothing_item_id, ClothingItem.user_id == user_id
    ).first()
    if not clothing:
        return None
    wi = _link_item_to_wardrobe(
        db,
        wardrobe_id=wardrobe_id,
        clothing_item_id=clothing_item_id,
    )
    db.commit()
    db.refresh(wi)
    return wi


def ensure_item_in_main_wardrobe(
    db: Session,
    *,
    user_id: UUID,
    clothing_item_id: UUID,
) -> WardrobeItem:
    main_wardrobe = ensure_main_wardrobe(db, user_id)
    return _link_item_to_wardrobe(
        db,
        wardrobe_id=main_wardrobe.id,
        clothing_item_id=clothing_item_id,
    )


def remove_item_from_wardrobe(
    db: Session, wardrobe_id: UUID, user_id: UUID, clothing_item_id: UUID
) -> bool:
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        return False
    wi = (
        db.query(WardrobeItem)
        .filter(
            WardrobeItem.wardrobe_id == wardrobe_id,
            WardrobeItem.clothing_item_id == clothing_item_id,
        )
        .first()
    )
    if not wi:
        return False
    db.delete(wi)
    db.commit()
    return True


def move_item_between_wardrobes(
    db: Session,
    *,
    user_id: UUID,
    clothing_item_id: UUID,
    from_wardrobe_id: UUID,
    to_wardrobe_id: UUID,
) -> Optional[WardrobeItem]:
    source = get_wardrobe(db, from_wardrobe_id, user_id)
    target = get_wardrobe(db, to_wardrobe_id, user_id)
    if not source or not target:
        return None

    clothing = db.query(ClothingItem).filter(
        ClothingItem.id == clothing_item_id, ClothingItem.user_id == user_id
    ).first()
    if not clothing:
        return None

    existing = (
        db.query(WardrobeItem)
        .filter(
            WardrobeItem.wardrobe_id == from_wardrobe_id,
            WardrobeItem.clothing_item_id == clothing_item_id,
        )
        .first()
    )
    if not existing:
        return None

    db.delete(existing)
    db.flush()
    moved = _link_item_to_wardrobe(
        db,
        wardrobe_id=to_wardrobe_id,
        clothing_item_id=clothing_item_id,
    )
    db.commit()
    db.refresh(moved)
    return moved


def copy_item_to_wardrobe(
    db: Session,
    *,
    user_id: UUID,
    clothing_item_id: UUID,
    to_wardrobe_id: UUID,
) -> Optional[WardrobeItem]:
    return add_item_to_wardrobe(db, to_wardrobe_id, user_id, clothing_item_id)


def export_selection_to_wardrobe(
    db: Session,
    *,
    user_id: UUID,
    clothing_item_ids: list[UUID],
    name: str | None = None,
    description: str | None = None,
    cover_image_url: str | None = None,
    manual_tags: list[str] | None = None,
) -> Wardrobe:
    if not clothing_item_ids:
        raise ValueError("At least one clothing item must be selected")

    owned_items = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.user_id == user_id,
            ClothingItem.id.in_(clothing_item_ids),
        )
        .all()
    )
    owned_by_id = {item.id: item for item in owned_items}
    missing = [item_id for item_id in clothing_item_ids if item_id not in owned_by_id]
    if missing:
        raise ValueError("One or more clothing items do not belong to the current user")

    main_wardrobe = ensure_main_wardrobe(db, user_id)
    user = db.get(User, user_id)
    auto_tags: list[str] = []
    for clothing_item_id in clothing_item_ids:
        auto_tags.extend(_tag_strings_for_item(owned_by_id[clothing_item_id]))
    if user is not None:
        auto_tags.append(user.username)
        auto_tags.append(f"uid:{user.uid}")

    wardrobe = Wardrobe(
        wid=_generate_wid(db),
        user_id=user_id,
        parent_wardrobe_id=main_wardrobe.id,
        name=name or _default_export_name(),
        kind="SUB",
        type="VIRTUAL",
        source="OUTFIT_EXPORT",
        description=description,
        cover_image_url=cover_image_url,
        auto_tags=_dedupe_tags(auto_tags),
        manual_tags=_dedupe_tags(manual_tags or []),
        is_public=False,
    )
    db.add(wardrobe)
    db.flush()

    for clothing_item_id in clothing_item_ids:
        _link_item_to_wardrobe(
            db,
            wardrobe_id=wardrobe.id,
            clothing_item_id=clothing_item_id,
        )

    db.commit()
    db.refresh(wardrobe)
    return wardrobe
