from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.creator import Pagination


OutfitPreviewStatus = Literal["PENDING", "PROCESSING", "COMPLETED", "FAILED"]
PersonViewType = Literal["FULL_BODY", "UPPER_BODY"]
GarmentCategory = Literal["TOP", "BOTTOM", "SHOES"]


class OutfitPreviewTaskCreateResponseData(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    id: UUID
    status: OutfitPreviewStatus
    clothing_item_ids: list[UUID] = Field(alias="clothingItemIds")
    person_view_type: PersonViewType = Field(alias="personViewType")
    garment_categories: list[GarmentCategory] = Field(alias="garmentCategories")
    created_at: datetime = Field(alias="createdAt")


class OutfitPreviewTaskCreateResponse(BaseModel):
    success: bool = True
    data: OutfitPreviewTaskCreateResponseData


class OutfitPreviewTaskItemSummary(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    clothing_item_id: UUID = Field(alias="clothingItemId")
    garment_category: GarmentCategory = Field(alias="garmentCategory")
    sort_order: int = Field(alias="sortOrder")


class OutfitPreviewTaskDetail(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    id: UUID
    status: OutfitPreviewStatus
    clothing_item_ids: list[UUID] = Field(alias="clothingItemIds")
    person_view_type: PersonViewType = Field(alias="personViewType")
    garment_categories: list[GarmentCategory] = Field(alias="garmentCategories")
    preview_image_url: str | None = Field(default=None, alias="previewImageUrl")
    error_code: str | None = Field(default=None, alias="errorCode")
    error_message: str | None = Field(default=None, alias="errorMessage")
    provider_name: str = Field(alias="providerName")
    provider_model: str = Field(alias="providerModel")
    created_at: datetime = Field(alias="createdAt")
    started_at: datetime | None = Field(default=None, alias="startedAt")
    completed_at: datetime | None = Field(default=None, alias="completedAt")
    items: list[OutfitPreviewTaskItemSummary] = Field(default_factory=list)


class OutfitPreviewTaskListItem(OutfitPreviewTaskDetail):
    pass


class OutfitPreviewTaskListData(BaseModel):
    items: list[OutfitPreviewTaskListItem]
    pagination: Pagination


class OutfitPreviewTaskListResponse(BaseModel):
    success: bool = True
    data: OutfitPreviewTaskListData


class OutfitItemSummary(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    id: UUID
    clothing_item_id: UUID = Field(alias="clothingItemId")
    created_at: datetime = Field(alias="createdAt")


class OutfitDetail(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    id: UUID
    user_id: UUID = Field(alias="userId")
    preview_task_id: UUID | None = Field(default=None, alias="previewTaskId")
    name: str | None = None
    preview_image_url: str = Field(alias="previewImageUrl")
    clothing_item_ids: list[UUID] = Field(alias="clothingItemIds")
    created_at: datetime = Field(alias="createdAt")
    updated_at: datetime = Field(alias="updatedAt")
    items: list[OutfitItemSummary] = Field(default_factory=list)


class OutfitPreviewSaveResponse(BaseModel):
    success: bool = True
    data: OutfitDetail
