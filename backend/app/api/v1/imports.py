# backend/app/api/v1/imports.py
"""Card pack import and un-import endpoints."""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.crud import wardrobe as crud_wardrobe
from app.db.session import get_db
from app.models.card_pack_import import CardPackImport
from app.models.clothing_item import ClothingItem, Image, Model3D
from app.models.creator import CardPack, CardPackItem
from app.models.wardrobe import WardrobeItem
from app.schemas.imports import ImportCardPackRequest, ImportCardPackResponse
from app.services.blob_service import get_blob_service
from app.services.blob_storage import BlobNotFoundError

router = APIRouter(prefix="/imports", tags=["Imports"])
logger = logging.getLogger(__name__)


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
