from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class StyledGenerationCreateResponse(BaseModel):
    id: UUID
    status: str
    estimatedTime: int = 120


class StyledGenerationGarmentSummary(BaseModel):
    id: UUID
    slot: str
    name: Optional[str] = None
    imageUrl: Optional[str] = None

    model_config = ConfigDict(populate_by_name=True)


class StyledGenerationResponse(BaseModel):
    id: UUID
    userId: UUID
    sourceClothingItemId: Optional[UUID] = None  # DEPRECATED (kept for back-compat)
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
    # NEW
    gender: str
    garments: list[StyledGenerationGarmentSummary] = []

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)
