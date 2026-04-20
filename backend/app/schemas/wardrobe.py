"""Module 3: Wardrobe API schemas."""
from datetime import datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, Field


class WardrobeBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    type: str = Field(default="REGULAR", pattern="^(REGULAR|VIRTUAL)$")
    description: Optional[str] = None
    cover_image_url: Optional[str] = Field(default=None, alias="coverImageUrl")
    manual_tags: List[str] = Field(default_factory=list, alias="manualTags")
    is_public: bool = Field(default=False, alias="isPublic")


class WardrobeCreate(WardrobeBase):
    pass


class WardrobeUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    cover_image_url: Optional[str] = Field(default=None, alias="coverImageUrl")
    manual_tags: Optional[List[str]] = Field(default=None, alias="manualTags")
    is_public: Optional[bool] = Field(default=None, alias="isPublic")


class WardrobeExportRequest(BaseModel):
    clothing_item_ids: List[UUID] = Field(alias="clothingItemIds", min_length=1)
    name: Optional[str] = Field(default=None, min_length=1, max_length=100)
    description: Optional[str] = None
    cover_image_url: Optional[str] = Field(default=None, alias="coverImageUrl")
    manual_tags: List[str] = Field(default_factory=list, alias="manualTags")


class WardrobeResponse(BaseModel):
    id: UUID
    wid: str
    userId: UUID
    ownerUid: Optional[str] = None
    ownerUsername: Optional[str] = None
    name: str
    kind: str
    type: str
    source: str
    isMain: bool
    description: Optional[str] = None
    coverImageUrl: Optional[str] = None
    autoTags: List[str] = []
    manualTags: List[str] = []
    tags: List[str] = []
    isPublic: bool = False
    parentWardrobeId: Optional[UUID] = None
    outfitId: Optional[UUID] = None
    itemCount: int
    createdAt: Optional[datetime] = None
    updatedAt: Optional[datetime] = None

    class Config:
        from_attributes = True


class WardrobeItemAdd(BaseModel):
    clothingItemId: UUID


class WardrobeItemMoveRequest(BaseModel):
    targetWardrobeId: UUID


class ClothingItemBrief(BaseModel):
    """Minimal clothing item for listing inside a wardrobe."""

    id: UUID
    name: Optional[str] = None
    description: Optional[str] = None
    source: str
    finalTags: List[dict] = []
    customTags: List[str] = []
    imageUrl: Optional[str] = None
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
