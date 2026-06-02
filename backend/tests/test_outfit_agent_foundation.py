from uuid import uuid4

import pytest

from app.schemas.agent import OutfitRecommendationRequest
from app.services.agent_llm_service import (
    AgentConfigurationError,
    OpenAICompatibleChatClient,
)
from app.services.clothing_taxonomy import get_clothing_taxonomy
from app.services.outfit_agent_service import OutfitRecommendationAgent


def test_taxonomy_contains_preview_mapping_and_weather_profiles():
    """Verifies Agent taxonomy exposes preview slots and weather profiles."""
    # Taxonomy is shared by `/attributes/options` and Agent tools, so these
    # assertions protect the main contract used by recommendation prompts.
    taxonomy = get_clothing_taxonomy()

    assert taxonomy["previewCategoryMapping"]["T_SHIRT"] == "TOP"
    assert taxonomy["previewCategoryMapping"]["JEANS"] == "BOTTOM"
    assert taxonomy["previewCategoryMapping"]["SNEAKERS"] == "SHOES"
    assert "summer_rain" in taxonomy["weatherProfiles"]
    assert "winter_snow" in taxonomy["weatherProfiles"]


def test_agent_graph_initializes():
    """Verifies the LangGraph workflow can be compiled."""
    # The client is not configured here because graph construction should not
    # call the provider; only runtime invocation validates LLM settings.
    agent = OutfitRecommendationAgent(llm=OpenAICompatibleChatClient())

    assert agent.graph is not None


def test_llm_client_requires_provider_configuration(monkeypatch):
    """Verifies missing provider settings fail before network calls."""
    from app.services import agent_llm_service

    # Clear every required field so the error reports all missing settings at
    # once instead of failing one configuration variable per run.
    monkeypatch.setattr(agent_llm_service.settings, "LLM_BASE_URL", None)
    monkeypatch.setattr(agent_llm_service.settings, "LLM_API_KEY", None)
    monkeypatch.setattr(agent_llm_service.settings, "LLM_MODEL", None)

    with pytest.raises(AgentConfigurationError) as exc:
        OpenAICompatibleChatClient().ensure_configured()

    assert "LLM_BASE_URL" in str(exc.value)
    assert "LLM_API_KEY" in str(exc.value)
    assert "LLM_MODEL" in str(exc.value)


def test_agent_request_aliases():
    """Verifies public camelCase request fields map to Python attributes."""
    wardrobe_id = uuid4()

    # The Flutter/API contract uses camelCase, while backend code uses
    # snake_case. This test protects that translation layer.
    request = OutfitRecommendationRequest.model_validate(
        {
            "message": "明天通勤穿什么",
            "targetDate": "2026-06-03",
            "wardrobeId": str(wardrobe_id),
            "generatePreview": True,
        }
    )

    assert request.wardrobe_id == wardrobe_id
    assert request.generate_preview is True
    assert request.model_dump(by_alias=True)["wardrobeId"] == wardrobe_id
