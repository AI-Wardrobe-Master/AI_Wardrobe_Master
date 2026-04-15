from fastapi import APIRouter

from app.api.v1 import (
    auth,
    card_packs,
    clothing,
    creator_items,
    creators,
    me,
    outfit_preview,
    styled_generation,
    wardrobe,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(me.router)
api_router.include_router(clothing.router)
api_router.include_router(card_packs.router)
api_router.include_router(creator_items.router)
api_router.include_router(creators.router)
api_router.include_router(outfit_preview.router)
api_router.include_router(wardrobe.router)
api_router.include_router(styled_generation.router)
