from datetime import date
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class AgentTagFilter(BaseModel):
    """Public request tag filter for the outfit recommendation endpoint."""

    model_config = ConfigDict(extra="forbid")

    key: str
    value: str


class OutfitRecommendationRequest(BaseModel):
    """Request body for one outfit recommendation Agent run."""

    model_config = ConfigDict(
        extra="forbid",
        populate_by_name=True,
        serialize_by_alias=True,
    )

    message: str = Field(min_length=1)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    city: str | None = None
    target_date: date | None = Field(default=None, alias="targetDate")
    wardrobe_id: UUID | None = Field(default=None, alias="wardrobeId")
    source: Literal["OWNED", "IMPORTED"] | None = None
    tags: list[AgentTagFilter] | None = None
    limit: int = Field(default=50, ge=1, le=100)
    generate_preview: bool = Field(default=False, alias="generatePreview")


class AgentToolResult(BaseModel):
    """Structured result returned by Agent tools."""

    status: Literal["success", "skipped", "failed"]
    error_code: str | None = Field(default=None, alias="errorCode")
    retryable: bool = False
    message_for_agent: str | None = Field(default=None, alias="messageForAgent")
    message_for_user: str | None = Field(default=None, alias="messageForUser")
    data: dict[str, Any] | None = None

    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)


class AgentToolTagInput(BaseModel):
    """Tag filter accepted by Agent tool calls."""

    model_config = ConfigDict(extra="forbid")

    key: str
    value: str


class SearchWardrobeItemsToolInput(BaseModel):
    """Input schema for the `search_wardrobe_items` Agent tool."""

    model_config = ConfigDict(extra="forbid")

    category: str | None = None
    source: Literal["OWNED", "IMPORTED"] | None = None
    tags: list[AgentToolTagInput] | None = None
    limit: int = Field(default=20, ge=1, le=50)


class OutfitRecommendationData(BaseModel):
    """Structured response data returned by the outfit Agent endpoint."""

    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    conversation_id: str | None = Field(default=None, alias="conversationId")
    provider_name: str = Field(alias="providerName")
    provider_model: str = Field(alias="providerModel")
    outfit: dict[str, Any]
    recommendation_reason: str = Field(alias="recommendationReason")
    weather_reason: str | None = Field(default=None, alias="weatherReason")
    preference_reason: str | None = Field(default=None, alias="preferenceReason")
    missing_items: list[str] = Field(default_factory=list, alias="missingItems")
    preview: AgentToolResult
    tools: dict[str, AgentToolResult]
    raw_model_output: dict[str, Any] | None = Field(default=None, alias="rawModelOutput")


class OutfitRecommendationResponse(BaseModel):
    """Top-level API response for outfit recommendation."""

    success: bool = True
    data: OutfitRecommendationData
