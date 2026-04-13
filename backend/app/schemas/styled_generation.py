from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class StyledGenerationCreateResponse(BaseModel):
    id: UUID
    status: str
    estimatedTime: int = 120


class StyledGenerationResponse(BaseModel):
    id: UUID
    userId: UUID
    sourceClothingItemId: Optional[UUID] = None
    selfieOriginalUrl: str
    selfieProcessedUrl: Optional[str] = None
    scenePrompt: str
    negativePrompt: Optional[str] = None
    dreamoVersion: str
    status: str
    progress: int
    resultImageUrl: Optional[str] = None
    failureReason: Optional[str] = None
    guidanceScale: float
    seed: int
    width: int
    height: int
    createdAt: datetime
    updatedAt: datetime

    model_config = {"from_attributes": True}
