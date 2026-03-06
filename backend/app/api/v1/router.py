"""
API v1 Router
"""
from fastapi import APIRouter

from app.api.v1 import ai, clothing

api_router = APIRouter()

api_router.include_router(ai.router, prefix="/ai", tags=["AI Classification"])
api_router.include_router(clothing.router, prefix="/clothing-items", tags=["Clothing Items"])
