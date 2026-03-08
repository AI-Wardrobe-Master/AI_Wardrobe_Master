"""Module 3: Wardrobe CRUD. Delete wardrobe only removes junction rows, not clothing_items."""
from typing import List, Optional, Tuple
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.wardrobe import Wardrobe, WardrobeItem
from app.models.clothing_item import ClothingItem


def list_wardrobes(db: Session, user_id: UUID) -> List[Wardrobe]:
    return db.query(Wardrobe).filter(Wardrobe.user_id == user_id).order_by(Wardrobe.created_at).all()


def get_wardrobe(db: Session, wardrobe_id: UUID, user_id: UUID) -> Optional[Wardrobe]:
    return (
        db.query(Wardrobe)
        .filter(Wardrobe.id == wardrobe_id, Wardrobe.user_id == user_id)
        .first()
    )


def create_wardrobe(
    db: Session,
    user_id: UUID,
    *,
    name: str,
    type: str = "REGULAR",
    description: Optional[str] = None,
) -> Wardrobe:
    w = Wardrobe(user_id=user_id, name=name, type=type, description=description)
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
) -> Optional[Wardrobe]:
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        return None
    if name is not None:
        w.name = name
    if description is not None:
        w.description = description
    db.commit()
    db.refresh(w)
    return w


def delete_wardrobe(db: Session, wardrobe_id: UUID, user_id: UUID) -> bool:
    """Delete wardrobe and its wardrobe_items only. Clothing items are untouched."""
    w = get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        return False
    db.delete(w)
    db.commit()
    return True


def get_item_count(db: Session, wardrobe_id: UUID) -> int:
    return db.query(func.count(WardrobeItem.id)).filter(WardrobeItem.wardrobe_id == wardrobe_id).scalar() or 0


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
        .filter(WardrobeItem.wardrobe_id == wardrobe_id)
        .order_by(WardrobeItem.display_order.nullslast(), WardrobeItem.added_at)
        .all()
    )
    return rows


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
    db.commit()
    db.refresh(wi)
    return wi


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
