# backend/app/api/v1/imports.py
"""Card pack import and un-import endpoints."""

import logging
import math
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.crud import wardrobe as crud_wardrobe
from app.db.session import get_db
from app.models.card_pack_import import CardPackImport
from app.models.clothing_item import ClothingItem, Image, Model3D
from app.models.creator import CardPack, CardPackItem, CreatorProfile
from app.models.user import User
from app.models.wardrobe import Wardrobe, WardrobeItem
from app.schemas.imports import (
    ImportCardPackRequest,
    ImportCardPackResponse,
    ImportHistoryData,
    ImportHistoryItem,
    ImportHistoryResponse,
    ImportWardrobeRequest,
    ImportWardrobeResponse,
)
from app.services.blob_service import get_blob_service
from app.services.blob_storage import BlobNotFoundError

router = APIRouter(prefix="/imports", tags=["Imports"])
logger = logging.getLogger(__name__)


def _dedupe_strings(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        cleaned = (value or "").strip()
        key = cleaned.lower()
        if not cleaned or key in seen:
            continue
        seen.add(key)
        result.append(cleaned)
    return result


def _delete_clothing_item_internal(db: Session, item: ClothingItem) -> None:
    """
    Delete a clothing item and release all its blob refs.
    Shared between DELETE /clothing-items/:id and un-import.
    """
    blob_service = get_blob_service()
    blob_hashes = [img.blob_hash for img in item.images if img.blob_hash]
    if item.model_3d and item.model_3d.blob_hash:
        blob_hashes.append(item.model_3d.blob_hash)

    db.query(WardrobeItem).filter(
        WardrobeItem.clothing_item_id == item.id,
    ).delete(synchronize_session=False)

    db.delete(item)
    db.flush()

    for h in blob_hashes:
        blob_service.release(db, h)


def _clone_clothing_item(
    db: Session,
    *,
    canonical: ClothingItem,
    user_id: UUID,
    target_wardrobe_id: UUID,
    blob_service,
) -> ClothingItem | None:
    if canonical.deleted_at is not None:
        return None

    new_item = ClothingItem(
        user_id=user_id,
        source="IMPORTED",
        name=canonical.name,
        description=canonical.description,
        predicted_tags=list(canonical.predicted_tags)
        if canonical.predicted_tags
        else [],
        final_tags=list(canonical.final_tags) if canonical.final_tags else [],
        is_confirmed=True,
        custom_tags=list(canonical.custom_tags) if canonical.custom_tags else [],
        category=canonical.category,
        material=canonical.material,
        style=canonical.style,
        preview_svg_state=canonical.preview_svg_state,
        preview_svg_available=canonical.preview_svg_available,
        catalog_visibility="PRIVATE",
        imported_from_card_pack_id=canonical.imported_from_card_pack_id,
        imported_from_clothing_item_id=canonical.id,
    )
    db.add(new_item)
    db.flush()

    for img in canonical.images:
        db.add(
            Image(
                clothing_item_id=new_item.id,
                image_type=img.image_type,
                angle=img.angle,
                blob_hash=img.blob_hash,
            )
        )
        try:
            blob_service.addref(db, img.blob_hash)
        except BlobNotFoundError:
            raise HTTPException(
                409,
                "Shared wardrobe contents changed during import; retry.",
            )

    if canonical.model_3d:
        db.add(
            Model3D(
                clothing_item_id=new_item.id,
                model_format=canonical.model_3d.model_format,
                blob_hash=canonical.model_3d.blob_hash,
                vertex_count=canonical.model_3d.vertex_count,
                face_count=canonical.model_3d.face_count,
            )
        )
        try:
            blob_service.addref(db, canonical.model_3d.blob_hash)
        except BlobNotFoundError:
            raise HTTPException(
                409,
                "Shared wardrobe contents changed during import; retry.",
            )

    crud_wardrobe.ensure_item_in_wardrobe(
        db,
        user_id=user_id,
        wardrobe_id=target_wardrobe_id,
        clothing_item_id=new_item.id,
    )
    return new_item


@router.get("/history", response_model=ImportHistoryResponse)
def list_import_history(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    query = db.query(CardPackImport).filter(CardPackImport.user_id == user_id)
    total = query.count()
    records = (
        query.order_by(CardPackImport.imported_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    return ImportHistoryResponse(
        data=ImportHistoryData(
            imports=[_to_import_history_item(db, record) for record in records],
            pagination={
                "page": page,
                "limit": limit,
                "total": total,
                "totalPages": math.ceil(total / limit) if total else 0,
            },
        )
    )


@router.post("/card-pack", status_code=201)
def import_card_pack(
    body: ImportCardPackRequest,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    pack = (
        db.query(CardPack)
        .filter(CardPack.id == body.card_pack_id, CardPack.status == "PUBLISHED")
        .with_for_update()
        .first()
    )
    if not pack:
        raise HTTPException(404, "Pack not found or not published")

    if pack.creator_id == user_id:
        raise HTTPException(409, "You cannot import your own card pack")

    existing = db.query(CardPackImport).filter_by(
        user_id=user_id, card_pack_id=pack.id,
    ).first()
    if existing:
        raise HTTPException(409, "Pack already imported")

    db.add(CardPackImport(user_id=user_id, card_pack_id=pack.id))

    blob_service = get_blob_service()
    main_wardrobe = crud_wardrobe.ensure_main_wardrobe(db, user_id)
    imported_item_ids: list[str] = []

    pack_items = (
        db.query(CardPackItem)
        .filter(CardPackItem.card_pack_id == pack.id)
        .order_by(CardPackItem.sort_order)
        .all()
    )

    for pi in pack_items:
        canonical = pi.clothing_item
        if canonical is None or canonical.deleted_at is not None:
            # Tombstoned or missing canonical item - skip silently.
            continue

        new_item = ClothingItem(
            user_id=user_id,
            source="IMPORTED",
            name=canonical.name,
            description=canonical.description,
            predicted_tags=list(canonical.predicted_tags) if canonical.predicted_tags else [],
            final_tags=list(canonical.final_tags) if canonical.final_tags else [],
            is_confirmed=True,
            custom_tags=[],
            catalog_visibility="PRIVATE",
            imported_from_card_pack_id=pack.id,
            imported_from_clothing_item_id=canonical.id,
        )
        db.add(new_item)
        db.flush()

        for img in canonical.images:
            db.add(Image(
                clothing_item_id=new_item.id,
                image_type=img.image_type,
                angle=img.angle,
                blob_hash=img.blob_hash,
            ))
            try:
                blob_service.addref(db, img.blob_hash)
            except BlobNotFoundError:
                raise HTTPException(
                    409,
                    "Pack contents changed during import; retry.",
                )

        if canonical.model_3d:
            db.add(Model3D(
                clothing_item_id=new_item.id,
                model_format=canonical.model_3d.model_format,
                blob_hash=canonical.model_3d.blob_hash,
                vertex_count=canonical.model_3d.vertex_count,
                face_count=canonical.model_3d.face_count,
            ))
            try:
                blob_service.addref(db, canonical.model_3d.blob_hash)
            except BlobNotFoundError:
                raise HTTPException(
                    409,
                    "Pack contents changed during import; retry.",
                )

        crud_wardrobe.ensure_item_in_wardrobe(
            db,
            user_id=user_id,
            wardrobe_id=main_wardrobe.id,
            clothing_item_id=new_item.id,
        )
        imported_item_ids.append(str(new_item.id))

    pack.import_count = (pack.import_count or 0) + 1
    db.commit()

    return ImportCardPackResponse(
        cardPackId=str(pack.id),
        importedItemIds=imported_item_ids,
    )


@router.post("/wardrobe", status_code=201, response_model=ImportWardrobeResponse)
def import_public_wardrobe(
    body: ImportWardrobeRequest,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    if body.wardrobe_id is None and not (body.wardrobe_wid or "").strip():
        raise HTTPException(422, "wardrobeWid or wardrobeId is required")

    source = None
    if body.wardrobe_id is not None:
        source = (
            db.query(Wardrobe)
            .filter(Wardrobe.id == body.wardrobe_id, Wardrobe.is_public.is_(True))
            .first()
        )
    else:
        source = crud_wardrobe.get_wardrobe_by_wid(
            db,
            body.wardrobe_wid or "",
            viewer_user_id=None,
        )
    if source is None:
        raise HTTPException(404, "Shared wardrobe not found")
    if source.user_id == user_id:
        raise HTTPException(409, "不能import自己发布的衣柜")

    rows = crud_wardrobe.list_public_wardrobe_items(db, source.id)
    if not rows:
        raise HTTPException(422, "Shared wardrobe has no importable clothing items")

    main_wardrobe = crud_wardrobe.ensure_main_wardrobe(db, user_id)
    auto_tags = _dedupe_strings(
        [
            *(source.auto_tags or []),
            *(source.manual_tags or []),
            source.wid,
            "imported",
        ]
    )
    target = crud_wardrobe.create_wardrobe(
        db,
        user_id,
        name=source.name,
        type="VIRTUAL",
        description=(
            source.description
            or f"Imported shared wardrobe {source.wid} into your wardrobe."
        ),
        cover_image_url=source.cover_image_url,
        manual_tags=list(source.manual_tags or []),
        source="IMPORTED",
        parent_wardrobe_id=main_wardrobe.id,
        auto_tags=auto_tags,
        is_public=False,
    )

    blob_service = get_blob_service()
    imported_item_ids: list[str] = []
    for _, canonical in rows:
        new_item = _clone_clothing_item(
            db,
            canonical=canonical,
            user_id=user_id,
            target_wardrobe_id=target.id,
            blob_service=blob_service,
        )
        if new_item is not None:
            imported_item_ids.append(str(new_item.id))

    db.commit()
    db.refresh(target)
    return ImportWardrobeResponse(
        wardrobeId=str(target.id),
        wardrobeWid=target.wid,
        importedItemIds=imported_item_ids,
    )


def _to_import_history_item(
    db: Session,
    record: CardPackImport,
) -> ImportHistoryItem:
    pack = db.get(CardPack, record.card_pack_id)
    creator_id = getattr(pack, "creator_id", None)
    creator_name = ""
    if creator_id is not None:
        profile = db.get(CreatorProfile, creator_id)
        user = db.get(User, creator_id)
        creator_name = (
            getattr(profile, "display_name", None)
            or getattr(user, "username", None)
            or str(creator_id)
        )

    item_count = db.query(ClothingItem).filter(
        ClothingItem.user_id == record.user_id,
        ClothingItem.imported_from_card_pack_id == record.card_pack_id,
    ).count()

    return ImportHistoryItem(
        id=str(record.id),
        userId=str(record.user_id),
        cardPackId=str(record.card_pack_id),
        cardPackName=getattr(pack, "name", None) or "Unknown card pack",
        creatorId=str(creator_id or ""),
        creatorName=creator_name,
        itemCount=item_count,
        importedAt=record.imported_at,
    )


@router.delete("/card-pack/{pack_id}", status_code=204)
def unimport_card_pack(
    pack_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    pack = (
        db.query(CardPack)
        .filter_by(id=pack_id)
        .with_for_update()
        .first()
    )

    record = db.query(CardPackImport).filter_by(
        user_id=user_id, card_pack_id=pack_id,
    ).first()
    if not record:
        raise HTTPException(404, "Not imported")

    items = db.query(ClothingItem).filter(
        ClothingItem.user_id == user_id,
        ClothingItem.imported_from_card_pack_id == pack_id,
    ).all()

    # Remember which canonical items these imports pointed at, so we can
    # hard-delete stale tombstones once the last import disappears.
    stale_canonicals = {
        item.imported_from_clothing_item_id
        for item in items
        if item.imported_from_clothing_item_id is not None
    }

    for item in items:
        _delete_clothing_item_internal(db, item)

    db.delete(record)

    if pack is not None and (pack.import_count or 0) > 0:
        pack.import_count -= 1

    # Cascade: if any canonical item the unimported items pointed to was a
    # tombstoned clothing item with no remaining imports referencing it,
    # hard-delete it so its blobs can be GC'd.
    for canonical_id in stale_canonicals:
        canonical = db.query(ClothingItem).filter_by(id=canonical_id).first()
        if canonical is None or canonical.deleted_at is None:
            continue
        remaining = (
            db.query(ClothingItem)
            .filter_by(imported_from_clothing_item_id=canonical_id)
            .count()
        )
        if remaining == 0:
            _delete_clothing_item_internal(db, canonical)

    db.commit()
