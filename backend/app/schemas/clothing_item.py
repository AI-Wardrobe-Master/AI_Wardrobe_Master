"""
Clothing item schemas - Module 2 tag structure
"""
from typing import Optional, List
from pydantic import BaseModel, Field


class Tag(BaseModel):
    """Tag = {key: string, value: string}, no confidence field"""
    key: str = Field(..., description="e.g. category, color, pattern")
    value: str = Field(..., description="e.g. T_SHIRT, blue, striped")


class ClothingItemBase(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    custom_tags: List[str] = Field(default_factory=list)


class ClothingItemUpdate(BaseModel):
    """PATCH /clothing-items/:id - tag confirmation and editing"""
    name: Optional[str] = None
    description: Optional[str] = None
    final_tags: Optional[List[Tag]] = Field(None, description="User-confirmed tags, replaces all")
    is_confirmed: Optional[bool] = None
    custom_tags: Optional[List[str]] = None
