"""Legacy shim. Forwards to /clothing-items with catalog_visibility='PACK_ONLY' default.
Remove in the next minor release."""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from app.api.deps import get_current_creator_user_id
from app.api.v1.clothing import (
    create_clothing_item,
    delete_clothing_item,
    get_clothing_item,
    update_clothing_item,
)
from app.db.session import get_db
from app.schemas.clothing_item import ClothingItemUpdate

router = APIRouter(prefix="/creator-items", tags=["creator-items (legacy)"])
logger = logging.getLogger(__name__)


@router.post("", status_code=202, deprecated=True)
async def legacy_create_creator_item(
    front_image: UploadFile = File(...),
    back_image: UploadFile | None = File(None),
    name: str | None = Form(None),
    description: str | None = Form(None),
    catalog_visibility: str = Form("PACK_ONLY", alias="catalogVisibility"),
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    logger.warning("Legacy /creator-items endpoint used; forward to /clothing-items.")
    return await create_clothing_item(
        front_image=front_image,
        back_image=back_image,
        name=name,
        description=description,
        custom_tags_json=None,
        category=None,
        material=None,
        style=None,
        wardrobe_id=None,
        catalog_visibility=catalog_visibility,
        db=db,
        user_id=creator_id,
    )


@router.get("/{item_id}", deprecated=True)
def legacy_get_creator_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    return get_clothing_item(item_id=item_id, db=db, user_id=creator_id)


@router.patch("/{item_id}", deprecated=True)
def legacy_update_creator_item(
    item_id: UUID,
    body: ClothingItemUpdate,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    return update_clothing_item(
        item_id=item_id, body=body, db=db, user_id=creator_id,
    )


@router.delete("/{item_id}", status_code=204, deprecated=True)
def legacy_delete_creator_item(
    item_id: UUID,
    db: Session = Depends(get_db),
    creator_id: UUID = Depends(get_current_creator_user_id),
):
    return delete_clothing_item(item_id=item_id, db=db, user_id=creator_id)
