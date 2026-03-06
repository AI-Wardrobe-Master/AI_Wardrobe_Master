from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from uuid import UUID


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
