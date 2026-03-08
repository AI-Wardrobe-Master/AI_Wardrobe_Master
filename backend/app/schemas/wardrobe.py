"""Module 3: Wardrobe API schemas."""
from datetime import datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, Field


class WardrobeBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    type: str = Field(default="REGULAR", pattern="^(REGULAR|VIRTUAL)$")
    description: Optional[str] = None


class WardrobeCreate(WardrobeBase):
    pass


class WardrobeUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None


class WardrobeResponse(BaseModel):
    id: UUID
    userId: UUID
    name: str
    type: str
    description: Optional[str] = None
    itemCount: int
    createdAt: Optional[datetime] = None
    updatedAt: Optional[datetime] = None

    class Config:
        from_attributes = True


class WardrobeItemAdd(BaseModel):
    clothingItemId: UUID


class ClothingItemBrief(BaseModel):
    """Minimal clothing item for listing inside a wardrobe."""
    id: UUID
    name: Optional[str] = None
    source: str
    finalTags: List[dict] = []
    addedAt: Optional[datetime] = None


class WardrobeItemResponse(BaseModel):
    id: UUID
    wardrobeId: UUID
    clothingItemId: UUID
    addedAt: Optional[datetime] = None
    displayOrder: Optional[int] = None
    clothingItem: Optional[ClothingItemBrief] = None

    class Config:
        from_attributes = True
