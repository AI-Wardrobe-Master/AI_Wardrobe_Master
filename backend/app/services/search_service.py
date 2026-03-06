"""
Search Service - Module 2.4.3
搜索使用 finalTags 仅，不使用 predictedTags。
"""
from typing import Optional, List, Tuple
from uuid import UUID

from sqlalchemy.orm import Session

from app.crud import clothing as crud_clothing
from app.models.clothing_item import ClothingItem
from app.schemas.clothing_item import Tag


class SearchService:
    """基于 final_tags 的服装搜索服务"""

    def search(
        self,
        db: Session,
        user_id: UUID,
        *,
        query: Optional[str] = None,
        filters: Optional[dict] = None,
        page: int = 1,
        limit: int = 20,
    ) -> Tuple[List[ClothingItem], int]:
        """
        POST /clothing-items/search 的实现。
        filters 可包含: source, tags (List[Tag])
        """
        tags = None
        source = None
        if filters:
            tags_raw = filters.get("tags")
            if tags_raw:
                tags = [
                    t if isinstance(t, dict) else {"key": t.key, "value": t.value}
                    for t in tags_raw
                ]
            source = filters.get("source")

        return crud_clothing.search_by_final_tags(
            db,
            user_id,
            tags=tags,
            source=source,
            query=query,
            page=page,
            limit=limit,
        )
