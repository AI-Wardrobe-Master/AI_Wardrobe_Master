from datetime import datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class Tag(BaseModel):
    key: str
    value: str


class ImageSetResponse(BaseModel):
    originalFrontUrl: str
    originalBackUrl: Optional[str] = None
    processedFrontUrl: Optional[str] = None
    processedBackUrl: Optional[str] = None
    angleViews: dict[int, str] = {}


class Model3DResponse(BaseModel):
    id: UUID
    modelFormat: str
    url: str
    vertexCount: Optional[int] = None
    faceCount: Optional[int] = None

    class Config:
        from_attributes = True


class ProcessingStatusResponse(BaseModel):
    status: str
    progress: int
    steps: dict[str, str] = {}
    errorMessage: Optional[str] = None


class ClothingItemCreateResponse(BaseModel):
    id: UUID
    processingTaskId: UUID
    status: str
    estimatedTime: int = 30


class ClothingItemResponse(BaseModel):
    id: UUID
    userId: UUID
    source: str
    images: ImageSetResponse
    model3dUrl: Optional[str] = None
    predictedTags: list[Tag] = []
    finalTags: list[Tag] = []
    isConfirmed: bool
    name: Optional[str] = None
    description: Optional[str] = None
    createdAt: datetime
    updatedAt: datetime

    class Config:
        from_attributes = True


class AngleViewsResponse(BaseModel):
    angleViews: dict[int, str]


class ClothingItemBase(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Optional[str] = None
    description: Optional[str] = None
    custom_tags: List[str] = Field(default_factory=list, alias="customTags")


class ClothingItemUpdate(BaseModel):
    """PATCH /clothing-items/:id - tag confirmation and editing"""
    model_config = ConfigDict(extra="forbid")

    name: Optional[str] = None
    description: Optional[str] = None
    final_tags: Optional[List[Tag]] = Field(
        None,
        alias="finalTags",
        description="User-confirmed tags, replaces all",
    )
    is_confirmed: Optional[bool] = Field(None, alias="isConfirmed")
    custom_tags: Optional[List[str]] = Field(None, alias="customTags")
