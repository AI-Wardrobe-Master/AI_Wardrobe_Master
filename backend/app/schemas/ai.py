"""
AI Classification API schemas
"""
from typing import List

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.clothing_item import Tag


class ClassifyRequest(BaseModel):
    """POST /ai/classify - input (API 使用 imageUrl)"""
    model_config = ConfigDict(extra="forbid")

    image_url: str = Field(..., alias="imageUrl")


class ClassifyResponseData(BaseModel):
    """POST /ai/classify - output data"""
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    predicted_tags: List[Tag] = Field(alias="predictedTags")


class ClassifyResponse(BaseModel):
    """POST /ai/classify - success envelope"""
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    success: bool
    data: ClassifyResponseData
