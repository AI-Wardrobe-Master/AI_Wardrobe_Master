from uuid import uuid4

import pytest

from app.schemas.agent import OutfitRecommendationRequest
from app.services.agent_llm_service import (
    AgentConfigurationError,
    OpenAICompatibleChatClient,
)
from app.services.clothing_taxonomy import get_clothing_taxonomy
from app.services.outfit_agent_service import OutfitRecommendationAgent
from app.services.outfit_agent_tools import OutfitAgentToolExecutor


class FakeFinalAnswerLLM:
    """Fake LLM that returns a final JSON answer without tool calls."""

    provider_name = "fake"
    model = "fake-model"

    def ensure_configured(self):
        """Matches the real LLM client configuration check."""
        return None

    def complete_message(self, messages, *, tools=None, tool_choice=None):
        """Returns a final assistant message for the Agent loop."""
        # This fake exercises the no-tool completion branch of the LangGraph
        # node without requiring a database session or network call.
        return {
            "role": "assistant",
            "content": (
                '{"outfit":{"name":"测试推荐","items":[]},"recommendationReason":'
                '"没有可用衣物，返回空推荐。","weatherReason":null,'
                '"preferenceReason":null,"missingItems":[],"userMessage":"测试"}'
            ),
        }


class FakeInvalidToolThenFinalLLM:
    """Fake LLM that first calls a bad tool, then returns final JSON."""

    provider_name = "fake"
    model = "fake-model"

    def __init__(self):
        """Initializes call tracking for assertions."""
        self.calls = 0
        self.seen_messages = []

    def ensure_configured(self):
        """Matches the real LLM client configuration check."""
        return None

    def complete_message(self, messages, *, tools=None, tool_choice=None):
        """Returns one invalid tool call and then a final response."""
        self.calls += 1
        self.seen_messages.append(messages)

        # First call asks for an invalid tag key. The executor should reject it
        # and send a structured tool failure back to the model.
        if self.calls == 1:
            return {
                "role": "assistant",
                "content": None,
                "tool_calls": [
                    {
                        "id": "call_bad_weather",
                        "type": "function",
                        "function": {
                            "name": "search_wardrobe_items",
                            "arguments": (
                                '{"tags":[{"key":"weather","value":"rain"}]}'
                            ),
                        },
                    }
                ],
            }

        return {
            "role": "assistant",
            "content": (
                '{"outfit":{"name":"降级推荐","items":[]},"recommendationReason":'
                '"工具参数失败后返回降级推荐。","weatherReason":null,'
                '"preferenceReason":null,"missingItems":[],"userMessage":"测试"}'
            ),
        }


class FakeReasonedItemLLM:
    """Fake LLM that returns an item-level reason to test normalization."""

    provider_name = "fake"
    model = "fake-model"

    def __init__(self, clothing_item_id):
        """Stores the returned clothing item id."""
        self.clothing_item_id = str(clothing_item_id)

    def ensure_configured(self):
        """Matches the real LLM client configuration check."""
        return None

    def complete_message(self, messages, *, tools=None, tool_choice=None):
        """Returns one selected item with an extra reason field."""
        return {
            "role": "assistant",
            "content": (
                '{"outfit":{"name":"测试推荐","items":[{"clothingItemId":"'
                + self.clothing_item_id
                + '","slot":"top","reason":"不应该保留"}]},'
                '"recommendationReason":"整体说明","weatherReason":null,'
                '"preferenceReason":null,"missingItems":[],"userMessage":"测试"}'
            ),
        }


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


def test_agent_loop_accepts_final_answer_without_tool_calls():
    """Verifies the LangGraph Agent can finish when no tools are requested."""
    agent = OutfitRecommendationAgent(llm=FakeFinalAnswerLLM())
    request = OutfitRecommendationRequest(message="今天穿什么")

    result = agent.run(
        None,
        user_id=uuid4(),
        request=request,
    )

    assert result["providerName"] == "fake"
    assert result["outfit"]["name"] == "测试推荐"
    assert result["outfit"]["items"] == []


def test_agent_loop_returns_tool_failure_to_model():
    """Verifies the Agent loop feeds tool failures back as tool messages."""
    llm = FakeInvalidToolThenFinalLLM()
    agent = OutfitRecommendationAgent(llm=llm)
    request = OutfitRecommendationRequest(message="下雨通勤穿什么")

    result = agent.run(
        None,
        user_id=uuid4(),
        request=request,
    )

    tool_messages = [
        message
        for message in llm.seen_messages[-1]
        if message.get("role") == "tool"
    ]
    assert result["outfit"]["name"] == "降级推荐"
    assert result["tools"]["search_wardrobe_items"].status == "failed"
    assert "INVALID_TOOL_ARGUMENTS" in tool_messages[0]["content"]


def test_agent_normalizes_item_level_reason():
    """Verifies final outfit items keep only id and slot fields."""
    clothing_item_id = str(uuid4())
    agent = OutfitRecommendationAgent(llm=FakeReasonedItemLLM(clothing_item_id))

    recommendation = agent._normalize_recommendation(
        {
            "outfit": {
                "name": "测试推荐",
                "items": [
                    {
                        "clothingItemId": clothing_item_id,
                        "slot": "top",
                        "reason": "不应该保留",
                    }
                ],
            },
            "recommendationReason": "整体说明",
            "missingItems": [],
        },
        [{"id": clothing_item_id}],
    )

    assert recommendation["outfit"]["items"] == [
        {"clothingItemId": clothing_item_id, "slot": "top"}
    ]


def test_search_tool_rejects_invalid_weather_tag_key():
    """Verifies wardrobe search validates model-provided tag keys."""
    taxonomy = get_clothing_taxonomy()
    executor = OutfitAgentToolExecutor(
        db=None,
        user_id=uuid4(),
        request=OutfitRecommendationRequest(message="下雨通勤穿什么"),
        taxonomy=taxonomy,
        clothing_payload_builder=lambda db, item: {},
    )

    result = executor.execute(
        tool_name="search_wardrobe_items",
        raw_arguments='{"tags":[{"key":"weather","value":"rain"}]}',
        cache={},
    )

    assert result.status == "failed"
    assert result.retryable is True
    assert result.error_code == "INVALID_TOOL_ARGUMENTS"
    assert "invalid tag key" in (result.message_for_agent or "")


def test_search_tool_cache_key_includes_request_limit():
    """Verifies per-run cache keys distinguish outer request limits."""
    taxonomy = get_clothing_taxonomy()
    user_id = uuid4()
    first = OutfitAgentToolExecutor(
        db=None,
        user_id=user_id,
        request=OutfitRecommendationRequest(message="通勤", limit=10),
        taxonomy=taxonomy,
        clothing_payload_builder=lambda db, item: {},
    )
    second = OutfitAgentToolExecutor(
        db=None,
        user_id=user_id,
        request=OutfitRecommendationRequest(message="通勤", limit=20),
        taxonomy=taxonomy,
        clothing_payload_builder=lambda db, item: {},
    )

    arguments = {"category": "SHIRT", "limit": 20}

    assert first.cache_key("search_wardrobe_items", arguments) != (
        second.cache_key("search_wardrobe_items", arguments)
    )


def test_search_tool_handles_missing_db_session():
    """Verifies a valid tool call degrades when DB session is unavailable."""
    taxonomy = get_clothing_taxonomy()
    executor = OutfitAgentToolExecutor(
        db=None,
        user_id=uuid4(),
        request=OutfitRecommendationRequest(message="下雨通勤穿什么"),
        taxonomy=taxonomy,
        clothing_payload_builder=lambda db, item: {},
    )

    result = executor.execute(
        tool_name="search_wardrobe_items",
        raw_arguments=(
            '{"category":"SHIRT","tags":[{"key":"weather_type","value":"rain"}]}'
        ),
        cache={},
    )

    assert result.status == "failed"
    assert result.retryable is False
    assert result.error_code == "DATABASE_SESSION_UNAVAILABLE"


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


def test_llm_client_sends_tool_calling_payload(monkeypatch):
    """Verifies the LLM client can send OpenAI-compatible tool schemas."""
    from app.services import agent_llm_service

    captured = {}

    class FakeResponse:
        """Minimal response object used by the fake HTTP client."""

        def raise_for_status(self):
            """Matches the httpx response API without raising."""
            # The fake provider accepts the request so the client can parse the
            # response body and expose the assistant tool call.
            return None

        def json(self):
            """Returns a provider-shaped assistant tool-call response."""
            return {
                "choices": [
                    {
                        "message": {
                            "role": "assistant",
                            "content": None,
                            "tool_calls": [
                                {
                                    "id": "call_1",
                                    "type": "function",
                                    "function": {
                                        "name": "search_wardrobe_items",
                                        "arguments": "{}",
                                    },
                                }
                            ],
                        }
                    }
                ]
            }

    class FakeClient:
        """Context-manager fake for `httpx.Client`."""

        def __init__(self, timeout):
            """Records the configured timeout."""
            captured["timeout"] = timeout

        def __enter__(self):
            """Returns the fake client inside a `with` block."""
            return self

        def __exit__(self, exc_type, exc, traceback):
            """Leaves the fake context manager without special handling."""
            return False

        def post(self, url, headers, json):
            """Captures the outgoing request and returns a fake response."""
            # The test inspects payload shape, not HTTP behavior.
            captured["url"] = url
            captured["headers"] = headers
            captured["json"] = json
            return FakeResponse()

    # Configure the client after monkeypatching settings so no environment file
    # or real provider is needed.
    monkeypatch.setattr(agent_llm_service.settings, "LLM_BASE_URL", "https://llm.test/v1")
    monkeypatch.setattr(agent_llm_service.settings, "LLM_API_KEY", "test-key")
    monkeypatch.setattr(agent_llm_service.settings, "LLM_MODEL", "test-model")
    monkeypatch.setattr(agent_llm_service.httpx, "Client", FakeClient)

    client = OpenAICompatibleChatClient()
    message = client.complete_message(
        [{"role": "user", "content": "推荐一套穿搭"}],
        tools=[
            {
                "type": "function",
                "function": {
                    "name": "search_wardrobe_items",
                    "parameters": {"type": "object", "properties": {}},
                },
            }
        ],
        tool_choice="auto",
    )

    assert captured["json"]["model"] == "test-model"
    assert captured["json"]["tool_choice"] == "auto"
    assert captured["json"]["tools"][0]["function"]["name"] == "search_wardrobe_items"
    assert message["tool_calls"][0]["function"]["name"] == "search_wardrobe_items"


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
