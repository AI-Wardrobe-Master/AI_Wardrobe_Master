"""Module 3: Wardrobe management API."""
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.crud import wardrobe as crud_wardrobe
from app.db.session import get_db
from app.schemas.wardrobe import WardrobeCreate, WardrobeItemAdd, WardrobeUpdate

router = APIRouter(prefix="/wardrobes", tags=["wardrobes"])


def _wardrobe_to_response(w, item_count: int) -> dict:
    return {
        "id": str(w.id),
        "userId": str(w.user_id),
        "name": w.name,
        "type": w.type,
        "description": w.description,
        "itemCount": item_count,
        "createdAt": w.created_at.isoformat() if w.created_at else None,
        "updatedAt": w.updated_at.isoformat() if w.updated_at else None,
    }


@router.get("")
def list_wardrobes(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    wardrobes = crud_wardrobe.list_wardrobes(db, user_id)
    out = []
    for w in wardrobes:
        count = crud_wardrobe.get_item_count(db, w.id)
        out.append(_wardrobe_to_response(w, count))
    return {"items": out}


@router.post("", status_code=201)
def create_wardrobe(
    body: WardrobeCreate,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    w = crud_wardrobe.create_wardrobe(
        db, user_id, name=body.name, type=body.type, description=body.description
    )
    return _wardrobe_to_response(w, 0)


@router.get("/{wardrobe_id}")
def get_wardrobe(
    wardrobe_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    w = crud_wardrobe.get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        raise HTTPException(status_code=404, detail="Wardrobe not found")
    count = crud_wardrobe.get_item_count(db, w.id)
    return _wardrobe_to_response(w, count)


@router.patch("/{wardrobe_id}")
def update_wardrobe(
    wardrobe_id: UUID,
    body: WardrobeUpdate,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    w = crud_wardrobe.update_wardrobe(
        db, wardrobe_id, user_id, name=body.name, description=body.description
    )
    if not w:
        raise HTTPException(status_code=404, detail="Wardrobe not found")
    count = crud_wardrobe.get_item_count(db, w.id)
    return _wardrobe_to_response(w, count)


@router.delete("/{wardrobe_id}", status_code=204)
def delete_wardrobe(
    wardrobe_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    ok = crud_wardrobe.delete_wardrobe(db, wardrobe_id, user_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Wardrobe not found")


@router.get("/{wardrobe_id}/items")
def list_wardrobe_items(
    wardrobe_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    w = crud_wardrobe.get_wardrobe(db, wardrobe_id, user_id)
    if not w:
        raise HTTPException(status_code=404, detail="Wardrobe not found")
    rows = crud_wardrobe.list_wardrobe_items(db, wardrobe_id, user_id)
    items = []
    for wi, ci in rows:
        items.append({
            "id": str(wi.id),
            "wardrobeId": str(wi.wardrobe_id),
            "clothingItemId": str(wi.clothing_item_id),
            "addedAt": wi.added_at.isoformat() if wi.added_at else None,
            "displayOrder": wi.display_order,
            "clothingItem": {
                "id": str(ci.id),
                "name": ci.name,
                "source": ci.source,
                "finalTags": ci.final_tags or [],
                "addedAt": wi.added_at.isoformat() if wi.added_at else None,
            },
        })
    return {"items": items}


@router.post("/{wardrobe_id}/items", status_code=201)
def add_item_to_wardrobe(
    wardrobe_id: UUID,
    body: WardrobeItemAdd,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    wi = crud_wardrobe.add_item_to_wardrobe(
        db, wardrobe_id, user_id, body.clothingItemId
    )
    if not wi:
        raise HTTPException(
            status_code=404,
            detail="Wardrobe not found or clothing item not found or not owned by user",
        )
    return {
        "id": str(wi.id),
        "wardrobeId": str(wi.wardrobe_id),
        "clothingItemId": str(wi.clothing_item_id),
        "addedAt": wi.added_at.isoformat() if wi.added_at else None,
        "displayOrder": wi.display_order,
    }


@router.delete("/{wardrobe_id}/items/{clothing_item_id}", status_code=204)
def remove_item_from_wardrobe(
    wardrobe_id: UUID,
    clothing_item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    ok = crud_wardrobe.remove_item_from_wardrobe(
        db, wardrobe_id, user_id, clothing_item_id
    )
    if not ok:
        raise HTTPException(
            status_code=404,
            detail="Wardrobe or wardrobe item link not found",
        )
