from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id, get_optional_current_user_id
from app.crud import card_pack as crud_card_pack
from app.crud import creator as crud_creator
from app.crud import creator_item as crud_creator_item
from app.db.session import get_db
from app.models.user import User
from app.schemas.card_pack import (
    CardPackListData,
    CardPackListItem,
    CardPackListResponse,
)
from app.schemas.creator import (
    CreatorDetail,
    CreatorItemListData,
    CreatorItemListResponse,
    CreatorListData,
    CreatorListItem,
    CreatorListResponse,
    CreatorProfileResponse,
    CreatorProfileUpdate,
    Pagination,
)
from app.services.storage_service import get_storage_service

router = APIRouter(prefix="/creators", tags=["creators"])


@router.get("", response_model=CreatorListResponse)
def list_creators(
    verified: bool | None = Query(None),
    search: str | None = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    rows, total = crud_creator.list_public_creators(
        db,
        verified=verified,
        search=search,
        page=page,
        limit=limit,
    )
    storage = get_storage_service()
    items = [
        CreatorListItem(
            id=profile.user_id,
            username=user.username,
            displayName=profile.display_name,
            brandName=profile.brand_name,
            avatarUrl=storage.get_url(profile.avatar_storage_path)
            if profile.avatar_storage_path
            else None,
            bioSummary=_bio_summary(profile.bio),
            packCount=crud_card_pack.count_published_card_packs_by_creator(
                db,
                creator_id=profile.user_id,
            ),
            isVerified=profile.is_verified,
        )
        for profile, user in rows
    ]
    return CreatorListResponse(
        data=CreatorListData(
            items=items,
            pagination=Pagination.build(page=page, limit=limit, total=total),
        )
    )


@router.get("/{creator_id}", response_model=CreatorProfileResponse)
def get_creator_profile(
    creator_id: UUID,
    db: Session = Depends(get_db),
):
    row = crud_creator.get_public_creator_profile(db, creator_id=creator_id)
    if row is None:
        raise HTTPException(404, "Creator not found")
    profile, user = row
    return CreatorProfileResponse(data=_to_creator_detail(profile, user.username))


@router.patch("/{creator_id}", response_model=CreatorProfileResponse)
def update_creator_profile(
    creator_id: UUID,
    body: CreatorProfileUpdate,
    db: Session = Depends(get_db),
    current_user_id: UUID = Depends(get_current_user_id),
):
    profile = crud_creator.get_owned_creator_profile(
        db,
        creator_id=creator_id,
        current_user_id=current_user_id,
    )
    if profile is None:
        raise HTTPException(404, "Creator profile not found")
    updated = crud_creator.update_profile(
        db,
        profile,
        display_name=body.display_name,
        brand_name=body.brand_name,
        bio=body.bio,
        website_url=body.website_url,
        social_links=body.social_links,
    )
    user = db.get(User, creator_id)
    return CreatorProfileResponse(data=_to_creator_detail(updated, user.username))


@router.get("/{creator_id}/items", response_model=CreatorItemListResponse)
def list_creator_items(
    creator_id: UUID,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    row = crud_creator.get_public_creator_profile(db, creator_id=creator_id)
    if row is None:
        raise HTTPException(404, "Creator not found")
    items, total = crud_creator_item.list_public_creator_items_by_creator(
        db,
        creator_id=creator_id,
        page=page,
        limit=limit,
    )
    storage = get_storage_service()
    response_items = []
    for item in items:
        cover_path = next(
            (
                image.storage_path
                for image in item.images
                if image.image_type == "PROCESSED_FRONT"
            ),
            None,
        ) or next(
            (
                image.storage_path
                for image in item.images
                if image.image_type == "ORIGINAL_FRONT"
            ),
            None,
        )
        response_items.append(
            {
                "id": item.id,
                "creatorId": item.creator_id,
                "catalogVisibility": item.catalog_visibility,
                "processingStatus": item.processing_status,
                "name": item.name,
                "description": item.description,
                "coverUrl": storage.get_url(cover_path) if cover_path else None,
                "finalTags": item.final_tags or [],
                "createdAt": item.created_at,
            }
        )
    return CreatorItemListResponse(
        data=CreatorItemListData(
            items=response_items,
            pagination=Pagination.build(page=page, limit=limit, total=total),
        )
    )


@router.get("/{creator_id}/card-packs", response_model=CardPackListResponse)
def list_creator_card_packs(
    creator_id: UUID,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user_id: UUID | None = Depends(get_optional_current_user_id),
):
    if current_user_id == creator_id:
        profile = crud_creator.get_by_user_id(db, creator_id)
        include_unpublished = True
    else:
        profile = crud_creator.get_public_creator_profile(db, creator_id=creator_id)
        include_unpublished = False
    if profile is None:
        raise HTTPException(404, "Creator not found")

    packs, total = crud_card_pack.list_creator_card_packs(
        db,
        creator_id=creator_id,
        include_unpublished=include_unpublished,
        page=page,
        limit=limit,
    )
    response_items = [_to_card_pack_list_item(pack) for pack in packs]
    return CardPackListResponse(
        data=CardPackListData(
            items=response_items,
            pagination=Pagination.build(page=page, limit=limit, total=total),
        )
    )


def _bio_summary(bio: str | None) -> str | None:
    if not bio:
        return None
    trimmed = bio.strip()
    if len(trimmed) <= 120:
        return trimmed
    return f"{trimmed[:117]}..."


def _to_creator_detail(profile, username: str) -> CreatorDetail:
    storage = get_storage_service()
    return CreatorDetail(
        id=profile.user_id,
        username=username,
        status=profile.status,
        displayName=profile.display_name,
        brandName=profile.brand_name,
        bio=profile.bio,
        avatarUrl=storage.get_url(profile.avatar_storage_path)
        if profile.avatar_storage_path
        else None,
        websiteUrl=profile.website_url,
        socialLinks=profile.social_links or {},
        isVerified=profile.is_verified,
        verifiedAt=profile.verified_at,
        createdAt=profile.created_at,
        updatedAt=profile.updated_at,
    )


def _to_card_pack_list_item(pack) -> CardPackListItem:
    item_count = len(pack.items)
    return CardPackListItem(
        id=pack.id,
        creatorId=pack.creator_id,
        name=pack.name,
        description=pack.description,
        type=pack.pack_type,
        status=pack.status,
        coverImage=pack.cover_image_storage_path,
        shareId=pack.share_id,
        importCount=pack.import_count,
        publishedAt=pack.published_at,
        archivedAt=pack.archived_at,
        itemCount=item_count,
        createdAt=pack.created_at,
        updatedAt=pack.updated_at,
    )
