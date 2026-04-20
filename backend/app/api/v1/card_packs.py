from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_creator_user_id, get_optional_current_user_id
from app.core.config import settings
from app.crud import card_pack as crud_card_pack
from app.crud import creator as crud_creator
from app.db.session import get_db
from app.models.card_pack_import import CardPackImport
from app.models.creator import CardPackItem
from app.models.user import User
from app.schemas.card_pack import (
    CardPackCreate,
    CardPackDetail,
    CardPackDetailResponse,
    CardPackListData,
    CardPackListItem,
    CardPackListResponse,
    CardPackItemSummary,
    CardPackPublishData,
    CardPackPublishResponse,
    CardPackUpdate,
)
from app.services.blob_service import get_blob_service

router = APIRouter(prefix="/card-packs", tags=["card-packs"])


@router.get("", response_model=CardPackListResponse)
def list_card_packs(
    status: str | None = Query(None),
    search: str | None = Query(None, min_length=1),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    if status not in (None, "PUBLISHED"):
        raise HTTPException(422, "Only published card packs are available in the public feed")
    packs, total = crud_card_pack.list_public_card_packs(
        db,
        search=search,
        page=page,
        limit=limit,
    )
    return CardPackListResponse(
        data=CardPackListData(
            items=[_to_card_pack_list_item(db, pack) for pack in packs],
            pagination={
                "page": page,
                "limit": limit,
                "total": total,
                "totalPages": (total + limit - 1) // limit if total else 0,
            },
        )
    )


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
    return CardPackDetailResponse(data=_to_card_pack_detail(db, pack))


@router.get("/popular", response_model=CardPackListResponse)
def list_popular_card_packs(
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
):
    packs = crud_card_pack.list_popular_card_packs(db, limit=limit)
    return CardPackListResponse(
        data=CardPackListData(
            items=[_to_card_pack_list_item(db, pack) for pack in packs],
            pagination={
                "page": 1,
                "limit": limit,
                "total": len(packs),
                "totalPages": 1,
            },
        )
    )


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
    return CardPackDetailResponse(data=_to_card_pack_detail(db, pack))


@router.get("/share/{share_id}", response_model=CardPackDetailResponse)
def get_card_pack_by_share_id(
    share_id: str,
    db: Session = Depends(get_db),
):
    pack = crud_card_pack.get_public_card_pack(db, share_id=share_id)
    if pack is None:
        raise HTTPException(404, "Card pack not found")
    return CardPackDetailResponse(data=_to_card_pack_detail(db, pack))


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
    return CardPackDetailResponse(data=_to_card_pack_detail(db, updated))


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
    detail = _to_card_pack_detail(db, published)
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
    return CardPackDetailResponse(data=_to_card_pack_detail(db, archived))


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
    import_count = (
        db.query(CardPackImport)
        .filter_by(card_pack_id=pack_id)
        .with_for_update()
        .count()
    )
    if import_count > 0:
        raise HTTPException(409, f"{import_count} user(s) have imported this pack")
    cover_blob_hash = pack.cover_image_blob_hash
    crud_card_pack.delete_card_pack(db, pack)
    if cover_blob_hash:
        blob_service = get_blob_service()
        blob_service.release(db, cover_blob_hash)
        db.commit()
    return None


def _to_card_pack_list_item(db: Session, pack) -> CardPackListItem:
    creator = db.get(User, pack.creator_id)
    linked_wardrobe = getattr(pack, "linked_wardrobe", None)
    return CardPackListItem(
        id=pack.id,
        creatorId=pack.creator_id,
        creatorUid=creator.uid if creator else None,
        creatorUsername=creator.username if creator else None,
        name=pack.name,
        description=pack.description,
        type=pack.pack_type,
        status=pack.status,
        coverImage=f"/files/card-packs/{pack.id}/cover" if pack.cover_image_blob_hash else None,
        wardrobeId=pack.wardrobe_id,
        wardrobeWid=linked_wardrobe.wid if linked_wardrobe else None,
        shareId=pack.share_id,
        importCount=pack.import_count,
        viewCount=pack.view_count or 0,
        publishedAt=pack.published_at,
        archivedAt=pack.archived_at,
        itemCount=len(pack.items),
        createdAt=pack.created_at,
        updatedAt=pack.updated_at,
    )


def _to_card_pack_detail(db: Session, pack) -> CardPackDetail:
    creator = db.get(User, pack.creator_id)
    linked_wardrobe = getattr(pack, "linked_wardrobe", None)
    items = [
        _to_card_pack_item_summary(db, pack_item)
        for pack_item in pack.items
    ]
    return CardPackDetail(
        id=pack.id,
        creatorId=pack.creator_id,
        creatorUid=creator.uid if creator else None,
        creatorUsername=creator.username if creator else None,
        name=pack.name,
        description=pack.description,
        type=pack.pack_type,
        status=pack.status,
        coverImage=f"/files/card-packs/{pack.id}/cover" if pack.cover_image_blob_hash else None,
        wardrobeId=pack.wardrobe_id,
        wardrobeWid=linked_wardrobe.wid if linked_wardrobe else None,
        shareId=pack.share_id,
        importCount=pack.import_count,
        viewCount=pack.view_count or 0,
        publishedAt=pack.published_at,
        archivedAt=pack.archived_at,
        itemCount=len(items),
        createdAt=pack.created_at,
        updatedAt=pack.updated_at,
        items=items,
    )


def _to_card_pack_item_summary(
    db: Session,
    pack_item: CardPackItem,
) -> CardPackItemSummary:
    from app.services.processing_task_service import get_latest_task

    clothing_item = pack_item.clothing_item
    cover_url = None
    processing_status = "PENDING"
    if clothing_item is not None:
        has_processed = any(
            image.image_type == "PROCESSED_FRONT"
            for image in clothing_item.images
        )
        if has_processed:
            cover_url = f"/files/clothing-items/{clothing_item.id}/processed-front"
        elif any(image.image_type == "ORIGINAL_FRONT" for image in clothing_item.images):
            cover_url = f"/files/clothing-items/{clothing_item.id}/original-front"
        latest_task = get_latest_task(db, clothing_item.id)
        if latest_task is not None:
            processing_status = latest_task.status
        elif clothing_item.images:
            processing_status = "COMPLETED"
    return CardPackItemSummary(
        id=pack_item.id,
        clothingItemId=pack_item.clothing_item_id,
        sortOrder=pack_item.sort_order,
        name=clothing_item.name if clothing_item else None,
        description=clothing_item.description if clothing_item else None,
        catalogVisibility=clothing_item.catalog_visibility if clothing_item else "PACK_ONLY",
        processingStatus=processing_status,
        coverUrl=cover_url,
        finalTags=(clothing_item.final_tags or []) if clothing_item else [],
        viewCount=(clothing_item.view_count or 0) if clothing_item else 0,
        createdAt=pack_item.created_at,
    )
