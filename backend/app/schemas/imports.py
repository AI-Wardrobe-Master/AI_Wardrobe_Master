# backend/app/schemas/imports.py
from uuid import UUID
from pydantic import BaseModel


class ImportCardPackRequest(BaseModel):
    card_pack_id: UUID


class ImportCardPackResponse(BaseModel):
    cardPackId: str
    importedItemIds: list[str]
