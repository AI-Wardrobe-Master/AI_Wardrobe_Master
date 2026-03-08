from fastapi import APIRouter

from app.api.v1 import ai, attributes, clothing

api_router = APIRouter()
api_router.include_router(ai.router, prefix="/ai", tags=["AI Classification"])
api_router.include_router(attributes.router)
api_router.include_router(clothing.router)
