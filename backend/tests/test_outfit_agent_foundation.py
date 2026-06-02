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
    taxonomy = get_clothing_taxonomy()

    assert taxonomy["previewCategoryMapping"]["T_SHIRT"] == "TOP"
    assert taxonomy["previewCategoryMapping"]["JEANS"] == "BOTTOM"
    assert taxonomy["previewCategoryMapping"]["SNEAKERS"] == "SHOES"
    assert "summer_rain" in taxonomy["weatherProfiles"]
    assert "winter_snow" in taxonomy["weatherProfiles"]


def test_agent_graph_initializes():
    agent = OutfitRecommendationAgent(llm=OpenAICompatibleChatClient())

    assert agent.graph is not None


def test_llm_client_requires_provider_configuration(monkeypatch):
    from app.services import agent_llm_service

    monkeypatch.setattr(agent_llm_service.settings, "LLM_BASE_URL", None)
    monkeypatch.setattr(agent_llm_service.settings, "LLM_API_KEY", None)
    monkeypatch.setattr(agent_llm_service.settings, "LLM_MODEL", None)

    with pytest.raises(AgentConfigurationError) as exc:
        OpenAICompatibleChatClient().ensure_configured()

    assert "LLM_BASE_URL" in str(exc.value)
    assert "LLM_API_KEY" in str(exc.value)
    assert "LLM_MODEL" in str(exc.value)


def test_agent_request_aliases():
    wardrobe_id = uuid4()

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
