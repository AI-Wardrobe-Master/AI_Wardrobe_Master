"""
Search API schemas
"""
from typing import Optional, List
from pydantic import BaseModel

from app.schemas.clothing_item import Tag


class SearchFilters(BaseModel):
    source: Optional[str] = None  # OWNED | IMPORTED
    tags: Optional[List[Tag]] = None


class SearchRequest(BaseModel):
    """POST /clothing-items/search - request body"""
    query: Optional[str] = None
    filters: Optional[SearchFilters] = None
    page: int = 1
    limit: int = 20
