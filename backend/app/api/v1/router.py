from fastapi import APIRouter

from app.api.v1 import clothing

api_router = APIRouter()
api_router.include_router(clothing.router)
