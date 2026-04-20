from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.clothing_item import Tag
from app.schemas.creator import Pagination


class CardPackCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=160)
    description: str | None = None
    pack_type: Literal["CLOTHING_COLLECTION"] = Field(
        default="CLOTHING_COLLECTION",
        alias="type",
    )
    item_ids: list[UUID] = Field(alias="itemIds", min_length=1)
    cover_image: str | None = Field(default=None, alias="coverImage")

    @field_validator("item_ids")
    @classmethod
    def _validate_unique_item_ids(cls, value: list[UUID]) -> list[UUID]:
        if len(value) != len(set(value)):
            raise ValueError("itemIds must be unique")
        return value


class CardPackUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, max_length=160)
    description: str | None = None
    item_ids: list[UUID] | None = Field(default=None, alias="itemIds")
    cover_image: str | None = Field(default=None, alias="coverImage")

    @field_validator("item_ids")
    @classmethod
    def _validate_unique_item_ids(cls, value: list[UUID] | None) -> list[UUID] | None:
        if value is not None and len(value) != len(set(value)):
            raise ValueError("itemIds must be unique")
        return value


class CardPackItemSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    creator_item_id: UUID = Field(alias="creatorItemId")
    sort_order: int = Field(alias="sortOrder")
    name: str | None = None
    description: str | None = None
    catalog_visibility: str = Field(alias="catalogVisibility")
    processing_status: str = Field(alias="processingStatus")
    cover_url: str | None = Field(default=None, alias="coverUrl")
    final_tags: list[Tag] = Field(default_factory=list, alias="finalTags")
    created_at: datetime = Field(alias="createdAt")


class CardPackBase(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    creator_id: UUID = Field(alias="creatorId")
    creator_uid: str | None = Field(default=None, alias="creatorUid")
    creator_username: str | None = Field(default=None, alias="creatorUsername")
    name: str
    description: str | None = None
    pack_type: str = Field(alias="type")
    status: str
    cover_image: str | None = Field(default=None, alias="coverImage")
    wardrobe_id: UUID | None = Field(default=None, alias="wardrobeId")
    wardrobe_wid: str | None = Field(default=None, alias="wardrobeWid")
    share_id: str | None = Field(default=None, alias="shareId")
    import_count: int = Field(alias="importCount")
    published_at: datetime | None = Field(default=None, alias="publishedAt")
    archived_at: datetime | None = Field(default=None, alias="archivedAt")
    item_count: int = Field(alias="itemCount")
    created_at: datetime = Field(alias="createdAt")
    updated_at: datetime = Field(alias="updatedAt")


class CardPackListItem(CardPackBase):
    pass


class CardPackDetail(CardPackBase):
    items: list[CardPackItemSummary] = Field(default_factory=list)


class CardPackPublishData(CardPackDetail):
    share_link: str = Field(alias="shareLink")


class CardPackListData(BaseModel):
    items: list[CardPackListItem]
    pagination: Pagination


class CardPackDetailResponse(BaseModel):
    success: bool = True
    data: CardPackDetail


class CardPackListResponse(BaseModel):
    success: bool = True
    data: CardPackListData


class CardPackPublishResponse(BaseModel):
    success: bool = True
    data: CardPackPublishData
