from datetime import datetime
from math import ceil
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.clothing_item import ImageSetResponse, Tag


class CreatorProfileSummary(BaseModel):
    exists: bool
    status: str | None = None
    display_name: str | None = Field(default=None, alias="displayName")
    brand_name: str | None = Field(default=None, alias="brandName")


class CreatorCapabilities(BaseModel):
    can_apply_for_creator: bool = Field(alias="canApplyForCreator")
    can_publish_items: bool = Field(alias="canPublishItems")
    can_create_card_packs: bool = Field(alias="canCreateCardPacks")
    can_edit_creator_profile: bool = Field(alias="canEditCreatorProfile")
    can_view_creator_center: bool = Field(alias="canViewCreatorCenter")


class MeData(BaseModel):
    id: UUID
    uid: str
    username: str
    email: str
    user_type: str = Field(alias="type")
    creator_profile: CreatorProfileSummary = Field(alias="creatorProfile")
    capabilities: CreatorCapabilities


class MeResponse(BaseModel):
    success: bool = True
    data: MeData


class CreatorProfileUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, alias="displayName")
    brand_name: str | None = Field(default=None, alias="brandName")
    bio: str | None = None
    website_url: str | None = Field(default=None, alias="websiteUrl")
    social_links: dict[str, str] | None = Field(default=None, alias="socialLinks")


class CreatorListItem(BaseModel):
    id: UUID
    username: str
    display_name: str = Field(alias="displayName")
    brand_name: str | None = Field(default=None, alias="brandName")
    avatar_url: str | None = Field(default=None, alias="avatarUrl")
    bio_summary: str | None = Field(default=None, alias="bioSummary")
    pack_count: int = Field(default=0, alias="packCount")
    is_verified: bool = Field(alias="isVerified")


class CreatorDetail(BaseModel):
    id: UUID
    username: str
    status: str
    display_name: str = Field(alias="displayName")
    brand_name: str | None = Field(default=None, alias="brandName")
    bio: str | None = None
    avatar_url: str | None = Field(default=None, alias="avatarUrl")
    website_url: str | None = Field(default=None, alias="websiteUrl")
    social_links: dict[str, str] = Field(default_factory=dict, alias="socialLinks")
    is_verified: bool = Field(alias="isVerified")
    verified_at: datetime | None = Field(default=None, alias="verifiedAt")
    created_at: datetime = Field(alias="createdAt")
    updated_at: datetime = Field(alias="updatedAt")


class Pagination(BaseModel):
    page: int
    limit: int
    total: int
    total_pages: int = Field(alias="totalPages")

    @classmethod
    def build(cls, *, page: int, limit: int, total: int) -> "Pagination":
        total_pages = ceil(total / limit) if limit else 0
        return cls(page=page, limit=limit, total=total, totalPages=total_pages)


class CreatorListData(BaseModel):
    items: list[CreatorListItem]
    pagination: Pagination


class CreatorListResponse(BaseModel):
    success: bool = True
    data: CreatorListData


class CreatorProfileResponse(BaseModel):
    success: bool = True
    data: CreatorDetail


class CreatorItemCreateResponseData(BaseModel):
    id: UUID
    processing_task_id: UUID = Field(alias="processingTaskId")
    status: str
    catalog_visibility: str = Field(alias="catalogVisibility")
    created_at: datetime = Field(alias="createdAt")


class CreatorItemCreateResponse(BaseModel):
    success: bool = True
    data: CreatorItemCreateResponseData


class CreatorItemUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = None
    description: str | None = None
    final_tags: list[Tag] | None = Field(default=None, alias="finalTags")
    custom_tags: list[str] | None = Field(default=None, alias="customTags")
    catalog_visibility: str | None = Field(default=None, alias="catalogVisibility")


class CreatorItemDetail(BaseModel):
    id: UUID
    creator_id: UUID = Field(alias="creatorId")
    catalog_visibility: str = Field(alias="catalogVisibility")
    processing_status: str = Field(alias="processingStatus")
    images: ImageSetResponse
    model3d_url: str | None = Field(default=None, alias="model3dUrl")
    predicted_tags: list[Tag] = Field(default_factory=list, alias="predictedTags")
    final_tags: list[Tag] = Field(default_factory=list, alias="finalTags")
    is_confirmed: bool = Field(alias="isConfirmed")
    name: str | None = None
    description: str | None = None
    custom_tags: list[str] = Field(default_factory=list, alias="customTags")
    created_at: datetime = Field(alias="createdAt")
    updated_at: datetime = Field(alias="updatedAt")


class CreatorItemResponse(BaseModel):
    success: bool = True
    data: CreatorItemDetail


class PublicCreatorItem(BaseModel):
    id: UUID
    creator_id: UUID = Field(alias="creatorId")
    catalog_visibility: str = Field(alias="catalogVisibility")
    processing_status: str = Field(alias="processingStatus")
    name: str | None = None
    description: str | None = None
    cover_url: str | None = Field(default=None, alias="coverUrl")
    final_tags: list[Tag] = Field(default_factory=list, alias="finalTags")
    created_at: datetime = Field(alias="createdAt")


class CreatorItemListData(BaseModel):
    items: list[PublicCreatorItem]
    pagination: Pagination


class CreatorItemListResponse(BaseModel):
    success: bool = True
    data: CreatorItemListData
