from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class TryOnImageData(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    id: UUID
    person_view_type: Literal["FULL_BODY", "UPPER_BODY"] = Field(
        alias="personViewType"
    )
    image_url: str = Field(alias="imageUrl")
    is_default: bool = Field(alias="isDefault")
    created_at: datetime = Field(alias="createdAt")
    updated_at: datetime = Field(alias="updatedAt")


class TryOnImageResponse(BaseModel):
    success: bool = True
    data: TryOnImageData | None = None
