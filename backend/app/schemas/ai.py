"""
AI Classification API schemas
"""
from typing import List
from pydantic import BaseModel, Field

from app.schemas.clothing_item import Tag


class ClassifyRequest(BaseModel):
    """POST /ai/classify - input (API 使用 imageUrl)"""
    image_url: str = Field(..., alias="imageUrl")

    model_config = {"populate_by_name": True}


class ClassifyResponse(BaseModel):
    """POST /ai/classify - output"""
    predicted_tags: List[Tag]
