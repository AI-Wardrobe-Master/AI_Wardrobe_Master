# backend/app/schemas/imports.py
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ImportCardPackRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    card_pack_id: UUID = Field(alias="cardPackId")


class ImportCardPackResponse(BaseModel):
    cardPackId: str
    importedItemIds: list[str]


class ImportWardrobeRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    wardrobe_wid: str | None = Field(default=None, alias="wardrobeWid")
    wardrobe_id: UUID | None = Field(default=None, alias="wardrobeId")


class ImportWardrobeResponse(BaseModel):
    wardrobeId: str
    wardrobeWid: str
    importedItemIds: list[str]


class ImportHistoryItem(BaseModel):
    id: str
    userId: str
    cardPackId: str
    cardPackName: str
    creatorId: str
    creatorName: str
    itemCount: int
    importedAt: datetime


class ImportHistoryData(BaseModel):
    imports: list[ImportHistoryItem]
    pagination: dict[str, int]


class ImportHistoryResponse(BaseModel):
    success: bool = True
    data: ImportHistoryData
