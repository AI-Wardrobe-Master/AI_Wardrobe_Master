# backend/app/api/v1/files.py
"""
Business-path file serving router.
Mounted at top-level /files (not under /api/v1) for backwards URL compat.
Resolves blob_hash internally; never exposes hashes to clients.
"""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.db.session import get_db
from app.models.blob import Blob
from app.models.clothing_item import ClothingItem, Image, Model3D
from app.models.creator import (
    CardPack,
    CreatorItem,
    CreatorItemImage,
    CreatorItemModel3D,
)
from app.models.outfit_preview import (
    Outfit,
    OutfitPreviewTask,
    OutfitPreviewTaskItem,
)
from app.models.styled_generation import StyledGeneration
from app.services.blob_storage import get_blob_storage

router = APIRouter()
logger = logging.getLogger(__name__)

_blob_storage = None


def _storage():
    global _blob_storage
    if _blob_storage is None:
        _blob_storage = get_blob_storage()
    return _blob_storage


IMAGE_KIND_MAP = {
    "original-front": ("ORIGINAL_FRONT", None),
    "original-back": ("ORIGINAL_BACK", None),
    "processed-front": ("PROCESSED_FRONT", None),
    "processed-back": ("PROCESSED_BACK", None),
    "angle-0": ("ANGLE_VIEW", 0),
    "angle-45": ("ANGLE_VIEW", 45),
    "angle-90": ("ANGLE_VIEW", 90),
    "angle-135": ("ANGLE_VIEW", 135),
    "angle-180": ("ANGLE_VIEW", 180),
    "angle-225": ("ANGLE_VIEW", 225),
    "angle-270": ("ANGLE_VIEW", 270),
    "angle-315": ("ANGLE_VIEW", 315),
}


async def _stream_blob(db: Session, blob_hash: str):
    """Look up blob metadata and return a StreamingResponse."""
    blob = db.query(Blob).filter(Blob.blob_hash == blob_hash).first()
    if not blob:
        raise HTTPException(404, "File not found")
    storage = _storage()
    return StreamingResponse(
        await storage.open_stream(blob_hash),
        media_type=blob.mime_type,
    )


# ---- Clothing item files ----

@router.get("/clothing-items/{item_id}/{kind}")
async def get_clothing_file(
    item_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = db.query(ClothingItem).filter(
        ClothingItem.id == item_id,
        ClothingItem.user_id == user_id,
    ).first()
    if not item:
        raise HTTPException(404)

    if kind == "model":
        model = db.query(Model3D).filter_by(clothing_item_id=item_id).first()
        if not model:
            raise HTTPException(404)
        blob = db.query(Blob).filter_by(blob_hash=model.blob_hash).first()
        storage = _storage()
        return StreamingResponse(
            await storage.open_stream(model.blob_hash),
            media_type="model/gltf-binary",
            headers={"Content-Disposition": f'attachment; filename="{item_id}.glb"'},
        )

    if kind not in IMAGE_KIND_MAP:
        raise HTTPException(404, f"Unknown image kind: {kind}")

    image_type, angle = IMAGE_KIND_MAP[kind]
    img = db.query(Image).filter_by(
        clothing_item_id=item_id,
        image_type=image_type,
        angle=angle,
    ).first()
    if not img:
        raise HTTPException(404)
    return await _stream_blob(db, img.blob_hash)


# ---- Creator item files ----

@router.get("/creator-items/{item_id}/{kind}")
async def get_creator_item_file(
    item_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    item = db.query(CreatorItem).filter(
        CreatorItem.id == item_id,
        CreatorItem.creator_id == user_id,
    ).first()
    if not item:
        raise HTTPException(404)

    if kind == "model":
        model = db.query(CreatorItemModel3D).filter_by(
            creator_item_id=item_id
        ).first()
        if not model:
            raise HTTPException(404)
        storage = _storage()
        return StreamingResponse(
            await storage.open_stream(model.blob_hash),
            media_type="model/gltf-binary",
        )

    if kind not in IMAGE_KIND_MAP:
        raise HTTPException(404)
    image_type, angle = IMAGE_KIND_MAP[kind]
    img = db.query(CreatorItemImage).filter_by(
        creator_item_id=item_id,
        image_type=image_type,
        angle=angle,
    ).first()
    if not img:
        raise HTTPException(404)
    return await _stream_blob(db, img.blob_hash)


# ---- Styled generation files ----

STYLED_GEN_KIND_MAP = {
    "selfie-original": "selfie_original_blob_hash",
    "selfie-processed": "selfie_processed_blob_hash",
    "result": "result_image_blob_hash",
}

@router.get("/styled-generations/{gen_id}/{kind}")
async def get_styled_generation_file(
    gen_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    gen = db.query(StyledGeneration).filter(
        StyledGeneration.id == gen_id,
        StyledGeneration.user_id == user_id,
    ).first()
    if not gen:
        raise HTTPException(404)

    attr = STYLED_GEN_KIND_MAP.get(kind)
    if not attr:
        raise HTTPException(404)
    blob_hash = getattr(gen, attr)
    if not blob_hash:
        raise HTTPException(404)
    return await _stream_blob(db, blob_hash)


# ---- Card pack cover ----

@router.get("/card-packs/{pack_id}/cover")
async def get_card_pack_cover(
    pack_id: UUID,
    db: Session = Depends(get_db),
):
    pack = db.query(CardPack).filter(CardPack.id == pack_id).first()
    if not pack or not pack.cover_image_blob_hash:
        raise HTTPException(404)
    return await _stream_blob(db, pack.cover_image_blob_hash)


# ---- Outfit preview files ----

@router.get("/outfit-preview-tasks/{task_id}/{kind}")
async def get_outfit_preview_file(
    task_id: UUID,
    kind: str,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    task = db.query(OutfitPreviewTask).filter(
        OutfitPreviewTask.id == task_id,
        OutfitPreviewTask.user_id == user_id,
    ).first()
    if not task:
        raise HTTPException(404)

    if kind == "person-image":
        return await _stream_blob(db, task.person_image_blob_hash)
    elif kind == "preview":
        if not task.preview_image_blob_hash:
            raise HTTPException(404)
        return await _stream_blob(db, task.preview_image_blob_hash)
    raise HTTPException(404)


@router.get("/outfits/{outfit_id}/preview")
async def get_outfit_preview(
    outfit_id: UUID,
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    outfit = db.query(Outfit).filter(
        Outfit.id == outfit_id,
        Outfit.user_id == user_id,
    ).first()
    if not outfit:
        raise HTTPException(404)
    return await _stream_blob(db, outfit.preview_image_blob_hash)
