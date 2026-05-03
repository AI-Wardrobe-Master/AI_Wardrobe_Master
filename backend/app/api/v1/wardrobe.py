"""Module 3: Wardrobe management API."""
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id, get_optional_current_user_id
from app.crud import wardrobe as crud_wardrobe
from app.db.session import get_db
from app.models.blob import Blob
from app.models.outfit_preview import Outfit
from app.models.user import User
from app.schemas.wardrobe import (
    WardrobeCreate,
    WardrobeExportRequest,
    WardrobeItemAdd,
    WardrobeItemMoveRequest,
    WardrobeUpdate,
)

router = APIRouter(prefix="/wardrobes", tags=["wardrobes"])


def _build_clothing_image_url(item) -> str | None:
    by_type = {image.image_type: image for image in item.images}
    if by_type.get("PROCESSED_FRONT") is not None:
        return f"/files/clothing-items/{item.id}/processed-front"
    if by_type.get("ORIGINAL_FRONT") is not None:
        return f"/files/clothing-items/{item.id}/original-front"
    if by_type.get("PROCESSED_BACK") is not None:
        return f"/files/clothing-items/{item.id}/processed-back"
    if by_type.get("ORIGINAL_BACK") is not None:
        return f"/files/clothing-items/{item.id}/original-back"
    return None


def _build_clothing_images(item) -> dict[str, str]:
    by_type = {image.image_type: image for image in item.images}
    payload: dict[str, str] = {}
    if by_type.get("ORIGINAL_FRONT") is not None:
        payload["originalFrontUrl"] = f"/files/clothing-items/{item.id}/original-front"
    if by_type.get("PROCESSED_FRONT") is not None:
        payload["processedFrontUrl"] = f"/files/clothing-items/{item.id}/processed-front"
    if by_type.get("ORIGINAL_BACK") is not None:
        payload["originalBackUrl"] = f"/files/clothing-items/{item.id}/original-back"
    if by_type.get("PROCESSED_BACK") is not None:
        payload["processedBackUrl"] = f"/files/clothing-items/{item.id}/processed-back"
    return payload


def _resolve_wardrobe_cover_url(db: Session, w) -> str | None:
    if w.cover_image_url:
        outfit_prefix = "/files/outfits/"
        outfit_suffix = "/preview"
        if (
            w.cover_image_url.startswith(outfit_prefix)
            and w.cover_image_url.endswith(outfit_suffix)
        ):
            outfit_id = w.cover_image_url[
                len(outfit_prefix) : -len(outfit_suffix)
            ]
            try:
                outfit = db.get(Outfit, UUID(outfit_id))
            except ValueError:
                outfit = None
            blob_exists = (
                outfit is not None
                and db.get(Blob, outfit.preview_image_blob_hash) is not None
            )
            if blob_exists:
                return w.cover_image_url
        else:
            return w.cover_image_url
    row = crud_wardrobe.list_public_wardrobe_items(db, w.id)
    if not row:
        return None
    _, item = row[0]
    return _build_clothing_image_url(item)


def _wardrobe_to_response(db: Session, w, item_count: int) -> dict:
    owner = db.get(User, w.user_id)
    auto_tags = list(w.auto_tags or [])
    manual_tags = list(w.manual_tags or [])
    return {
        "id": str(w.id),
        "wid": w.wid,
        "userId": str(w.user_id),
        "ownerUid": owner.uid if owner else None,
        "ownerUsername": owner.username if owner else None,
        "name": w.name,
        "kind": w.kind,
        "type": w.type,
        "source": w.source,
        "isMain": w.kind == "MAIN",
        "description": w.description,
        "coverImageUrl": _resolve_wardrobe_cover_url(db, w),
        "autoTags": auto_tags,
        "manualTags": manual_tags,
        "tags": [*auto_tags, *[tag for tag in manual_tags if tag not in auto_tags]],
        "isPublic": w.is_public,
        "parentWardrobeId": str(w.parent_wardrobe_id) if w.parent_wardrobe_id else None,
        "outfitId": str(w.outfit_id) if w.outfit_id else None,
        "itemCount": item_count,
        "createdAt": w.created_at.isoformat() if w.created_at else None,
        "updatedAt": w.updated_at.isoformat() if w.updated_at else None,
    }


def _wardrobe_item_to_response(wi, ci) -> dict:
    return {
        "id": str(wi.id),
        "wardrobeId": str(wi.wardrobe_id),
        "clothingItemId": str(wi.clothing_item_id),
        "addedAt": wi.added_at.isoformat() if wi.added_at else None,
        "displayOrder": wi.display_order,
        "clothingItem": {
            "id": str(ci.id),
            "name": ci.name,
            "description": ci.description,
            "source": ci.source,
            "finalTags": ci.final_tags or [],
            "customTags": ci.custom_tags or [],
            "category": ci.category,
            "material": ci.material,
            "style": ci.style,
            "imageUrl": _build_clothing_image_url(ci),
            "images": _build_clothing_images(ci),
            "addedAt": wi.added_at.isoformat() if wi.added_at else None,
        },
    }


@router.get("")
def list_wardrobes(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    wardrobes = crud_wardrobe.list_wardrobes(db, user_id)
    counts = crud_wardrobe.count_items_by_wardrobe_ids(db, [w.id for w in wardrobes])
    out = [_wardrobe_to_response(db, w, counts.get(w.id, 0)) for w in wardrobes]
    return {"items": out}


@router.get("/public")
def list_public_wardrobes(
    search: str | None = Query(None, min_length=1),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    wardrobes, total = crud_wardrobe.list_public_wardrobes(
        db,
        search=search,
        page=page,
        limit=limit,
    )
    counts = crud_wardrobe.count_items_by_wardrobe_ids(db, [w.id for w in wardrobes])
    items = [
        _wardrobe_to_response(db, w, counts.get(w.id, 0))
        for w in wardrobes
    ]
    return {
        "items": items,
        "pagination": {
            "page": page,
            "limit": limit,
            "total": total,
            "totalPages": (total + limit - 1) // limit if total else 0,
        },
    }


@router.get("/by-wid/{wid}")
def get_wardrobe_by_wid(
    wid: str,
    db: Session = Depends(get_db),
    viewer_user_id: UUID | None = Depends(get_optional_current_user_id),
):
    w = crud_wardrobe.get_wardrobe_by_wid(db, wid, viewer_user_id=viewer_user_id)
    if not w:
        raise HTTPException(status_code=404, detail="Wardrobe not found")
    count = crud_wardrobe.get_item_count(db, w.id)
    return _wardrobe_to_response(db, w, count)


@router.get("/by-wid/{wid}/items")
def list_wardrobe_items_by_wid(
    wid: str,
    db: Session = Depends(get_db),
    viewer_user_id: UUID | None = Depends(get_optional_current_user_id),
):
    wardrobe = crud_wardrobe.get_wardrobe_by_wid(
        db,
        wid,
        viewer_user_id=viewer_user_id,
    )
    if not wardrobe:
        raise HTTPException(status_code=404, detail="Wardrobe not found")
    rows = crud_wardrobe.list_public_wardrobe_items(db, wardrobe.id)
    return {"items": [_wardrobe_item_to_response(wi, ci) for wi, ci in rows]}


@router.post("", status_code=201)
def create_wardrobe(
    body: WardrobeCreate,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    main_wardrobe = crud_wardrobe.ensure_main_wardrobe(db, user_id)
    w = crud_wardrobe.create_wardrobe(
        db,
        user_id,
        name=body.name,
        type=body.type,
        description=body.description,
        cover_image_url=body.cover_image_url,
        manual_tags=body.manual_tags,
        is_public=body.is_public,
        parent_wardrobe_id=main_wardrobe.id,
    )
    return _wardrobe_to_response(db, w, 0)


@router.post("/export-selection", status_code=201)
def export_selection_to_wardrobe(
    body: WardrobeExportRequest,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    try:
        wardrobe = crud_wardrobe.export_selection_to_wardrobe(
            db,
            user_id=user_id,
            clothing_item_ids=body.clothing_item_ids,
            name=body.name,
            description=body.description,
            cover_image_url=body.cover_image_url,
            manual_tags=body.manual_tags,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return _wardrobe_to_response(
        db,
        wardrobe,
        crud_wardrobe.get_item_count(db, wardrobe.id),
    )


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
    return _wardrobe_to_response(db, w, count)


@router.patch("/{wardrobe_id}")
def update_wardrobe(
    wardrobe_id: UUID,
    body: WardrobeUpdate,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    w = crud_wardrobe.update_wardrobe(
        db,
        wardrobe_id,
        user_id,
        name=body.name,
        description=body.description,
        cover_image_url=body.cover_image_url,
        manual_tags=body.manual_tags,
        is_public=body.is_public,
    )
    if not w:
        raise HTTPException(status_code=404, detail="Wardrobe not found")
    count = crud_wardrobe.get_item_count(db, w.id)
    return _wardrobe_to_response(db, w, count)


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
    return {"items": [_wardrobe_item_to_response(wi, ci) for wi, ci in rows]}


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


@router.post("/{wardrobe_id}/items/{clothing_item_id}/move")
def move_item_between_wardrobes(
    wardrobe_id: UUID,
    clothing_item_id: UUID,
    body: WardrobeItemMoveRequest,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    moved = crud_wardrobe.move_item_between_wardrobes(
        db,
        user_id=user_id,
        clothing_item_id=clothing_item_id,
        from_wardrobe_id=wardrobe_id,
        to_wardrobe_id=body.targetWardrobeId,
    )
    if not moved:
        raise HTTPException(
            status_code=404,
            detail="Wardrobe, target wardrobe, or clothing item link not found",
        )
    return {
        "id": str(moved.id),
        "wardrobeId": str(moved.wardrobe_id),
        "clothingItemId": str(moved.clothing_item_id),
        "addedAt": moved.added_at.isoformat() if moved.added_at else None,
        "displayOrder": moved.display_order,
    }


@router.post("/{wardrobe_id}/items/{clothing_item_id}/copy", status_code=201)
def copy_item_to_wardrobe(
    wardrobe_id: UUID,
    clothing_item_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    copied = crud_wardrobe.copy_item_to_wardrobe(
        db,
        user_id=user_id,
        clothing_item_id=clothing_item_id,
        to_wardrobe_id=wardrobe_id,
    )
    if not copied:
        raise HTTPException(
            status_code=404,
            detail="Target wardrobe or clothing item not found",
        )
    return {
        "id": str(copied.id),
        "wardrobeId": str(copied.wardrobe_id),
        "clothingItemId": str(copied.clothing_item_id),
        "addedAt": copied.added_at.isoformat() if copied.added_at else None,
        "displayOrder": copied.display_order,
    }
