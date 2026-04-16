from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_creator_user_id, get_optional_current_user_id
from app.core.config import settings
from app.crud import card_pack as crud_card_pack
from app.crud import creator as crud_creator
from app.db.session import get_db
from app.models.card_pack_import import CardPackImport
from app.models.creator import CardPackItem
from app.schemas.card_pack import (
    CardPackCreate,
    CardPackDetail,
    CardPackDetailResponse,
    CardPackItemSummary,
    CardPackPublishData,
    CardPackPublishResponse,
    CardPackUpdate,
)
from app.services.blob_service import get_blob_service

router = APIRouter(prefix="/card-packs", tags=["card-packs"])


@router.post("", response_model=CardPackDetailResponse, status_code=201)
def create_card_pack(
    body: CardPackCreate,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    pack = crud_card_pack.create_card_pack(
        db,
        creator_id=creator_id,
        name=body.name,
        description=body.description,
        pack_type=body.pack_type,
        cover_image_blob_hash=body.cover_image,
        item_ids=body.item_ids,
    )
    return CardPackDetailResponse(data=_to_card_pack_detail(pack))


@router.get("/{pack_id}", response_model=CardPackDetailResponse)
def get_card_pack(
    pack_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: UUID | None = Depends(get_optional_current_user_id),
):
    pack = None
    if current_user_id is not None:
        pack = crud_card_pack.get_owned_card_pack(
            db,
            pack_id=pack_id,
            creator_id=current_user_id,
        )
    if pack is None:
        pack = crud_card_pack.get_public_card_pack(db, pack_id=pack_id)
    if pack is None:
        raise HTTPException(404, "Card pack not found")
    return CardPackDetailResponse(data=_to_card_pack_detail(pack))


@router.get("/share/{share_id}", response_model=CardPackDetailResponse)
def get_card_pack_by_share_id(
    share_id: str,
    db: Session = Depends(get_db),
):
    pack = crud_card_pack.get_public_card_pack(db, share_id=share_id)
    if pack is None:
        raise HTTPException(404, "Card pack not found")
    return CardPackDetailResponse(data=_to_card_pack_detail(pack))


@router.patch("/{pack_id}", response_model=CardPackDetailResponse)
def update_card_pack(
    pack_id: UUID,
    body: CardPackUpdate,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    pack = crud_card_pack.get_owned_card_pack(
        db,
        pack_id=pack_id,
        creator_id=creator_id,
        for_update=True,
    )
    if pack is None:
        raise HTTPException(404, "Card pack not found")
    updated = crud_card_pack.update_card_pack(
        db,
        pack,
        name=body.name,
        description=body.description,
        item_ids=body.item_ids,
        cover_image_blob_hash=body.cover_image,
    )
    return CardPackDetailResponse(
        data=_to_card_pack_detail(updated)
    )


@router.post("/{pack_id}/publish", response_model=CardPackPublishResponse)
def publish_card_pack(
    pack_id: UUID,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    pack = crud_card_pack.get_owned_card_pack(
        db,
        pack_id=pack_id,
        creator_id=creator_id,
        for_update=True,
    )
    if pack is None:
        raise HTTPException(404, "Card pack not found")
    published = crud_card_pack.publish_card_pack(db, pack)
    detail = _to_card_pack_detail(published)
    return CardPackPublishResponse(
        data=CardPackPublishData(
            **detail.model_dump(by_alias=True),
            shareLink=f"{settings.API_V1_STR}/card-packs/share/{published.share_id}",
        )
    )


@router.post("/{pack_id}/archive", response_model=CardPackDetailResponse)
def archive_card_pack(
    pack_id: UUID,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    pack = crud_card_pack.get_owned_card_pack(
        db,
        pack_id=pack_id,
        creator_id=creator_id,
        for_update=True,
    )
    if pack is None:
        raise HTTPException(404, "Card pack not found")
    archived = crud_card_pack.archive_card_pack(db, pack)
    return CardPackDetailResponse(
        data=_to_card_pack_detail(archived)
    )


@router.delete("/{pack_id}", status_code=204)
def delete_card_pack(
    pack_id: UUID,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    pack = crud_card_pack.get_owned_card_pack(
        db,
        pack_id=pack_id,
        creator_id=creator_id,
        for_update=True,
    )
    if pack is None:
        raise HTTPException(404, "Card pack not found")
    import_count = db.query(CardPackImport).filter_by(card_pack_id=pack_id).count()
    if import_count > 0:
        raise HTTPException(409, f"{import_count} user(s) have imported this pack")
    cover_blob_hash = pack.cover_image_blob_hash
    crud_card_pack.delete_card_pack(db, pack)
    if cover_blob_hash:
        blob_service = get_blob_service()
        blob_service.release(db, cover_blob_hash)
        db.commit()
    return None


def _to_card_pack_detail(pack) -> CardPackDetail:
    items = [
        _to_card_pack_item_summary(pack_item)
        for pack_item in pack.items
    ]
    return CardPackDetail(
        id=pack.id,
        creatorId=pack.creator_id,
        name=pack.name,
        description=pack.description,
        type=pack.pack_type,
        status=pack.status,
        coverImage=f"/files/card-packs/{pack.id}/cover" if pack.cover_image_blob_hash else None,
        shareId=pack.share_id,
        importCount=pack.import_count,
        publishedAt=pack.published_at,
        archivedAt=pack.archived_at,
        itemCount=len(items),
        createdAt=pack.created_at,
        updatedAt=pack.updated_at,
        items=items,
    )


def _to_card_pack_item_summary(
    pack_item: CardPackItem,
) -> CardPackItemSummary:
    creator_item = pack_item.creator_item
    cover_url = None
    if creator_item is not None:
        has_processed = any(
            image.image_type == "PROCESSED_FRONT"
            for image in creator_item.images
        )
        if has_processed:
            cover_url = f"/files/creator-items/{creator_item.id}/processed-front"
        elif any(image.image_type == "ORIGINAL_FRONT" for image in creator_item.images):
            cover_url = f"/files/creator-items/{creator_item.id}/original-front"
    return CardPackItemSummary(
        id=pack_item.id,
        creatorItemId=pack_item.creator_item_id,
        sortOrder=pack_item.sort_order,
        name=creator_item.name if creator_item else None,
        description=creator_item.description if creator_item else None,
        catalogVisibility=creator_item.catalog_visibility if creator_item else "PACK_ONLY",
        processingStatus=creator_item.processing_status if creator_item else "PENDING",
        coverUrl=cover_url,
        finalTags=(creator_item.final_tags or []) if creator_item else [],
        createdAt=pack_item.created_at,
    )
