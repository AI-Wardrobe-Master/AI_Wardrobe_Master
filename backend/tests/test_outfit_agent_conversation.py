"""Tests for JSONL-backed outfit Agent conversation history."""

from __future__ import annotations

import json
from pathlib import Path
from uuid import uuid4

from app.schemas.agent import OutfitRecommendationRequest
from app.services.conversation_store import JsonlConversationStore
from app.services.outfit_agent_service import OutfitRecommendationAgent


class CapturingConversationLLM:
    """Fake LLM that records recommendation-loop prompts."""

    provider_name = "fake"
    model = "fake-model"

    def __init__(self) -> None:
        """Initializes prompt capture state."""
        self.recommendation_messages: list[list[dict]] = []

    def ensure_configured(self) -> None:
        """Matches the real provider configuration check."""
        return None

    def complete_json(self, messages):
        """Returns minimal request-understanding output."""
        return {
            "intent": "new_outfit",
            "targetDate": None,
            "city": None,
            "weatherRequired": False,
            "occasion": None,
            "styleIntent": None,
            "carryOverPreviousOutfit": False,
            "revisionRequest": {"slot": None, "instruction": None},
            "userConstraints": [],
        }

    def complete_message(self, messages, *, tools=None, tool_choice=None):
        """Returns a deterministic final recommendation."""
        self.recommendation_messages.append(messages)
        return {
            "role": "assistant",
            "content": (
                '{"outfit":{"name":"会话测试","items":[]},'
                '"recommendationReason":"基于会话上下文。",'
                '"weatherReason":null,'
                '"preferenceReason":null,'
                '"missingItems":[],'
                '"userMessage":"已生成。"}'
            ),
        }


def test_jsonl_store_appends_turn_and_loads_context():
    """Verifies JSONL store persists user message and assistant result."""
    user_id = uuid4()
    store = JsonlConversationStore(_test_storage_dir())

    turn = store.append_turn(
        user_id=user_id,
        user_message="第一轮",
        assistant_result={
            "outfit": {"name": "第一套", "items": []},
            "recommendationReason": "测试",
        },
    )
    context = store.load_context(user_id=user_id, limit=5)

    assert turn["conversationId"] == f"user:{user_id}"
    assert context["conversationId"] == f"user:{user_id}"
    assert context["recentTurns"][0]["userMessage"] == "第一轮"
    assert context["lastRecommendation"]["outfit"]["name"] == "第一套"


def test_agent_loads_previous_turn_into_prompt():
    """Verifies second Agent run includes previous result in the prompt."""
    user_id = uuid4()
    llm = CapturingConversationLLM()
    store = JsonlConversationStore(_test_storage_dir())
    agent = OutfitRecommendationAgent(llm=llm, conversation_store=store)

    # First run creates the user's JSONL conversation file.
    agent.run(
        None,
        user_id=user_id,
        request=OutfitRecommendationRequest(message="先推荐一套"),
    )
    agent.run(
        None,
        user_id=user_id,
        request=OutfitRecommendationRequest(message="把鞋子换休闲一点"),
    )

    second_prompt = json.loads(llm.recommendation_messages[-1][1]["content"])
    conversation_context = second_prompt["conversationContext"]

    assert conversation_context["conversationId"] == f"user:{user_id}"
    assert conversation_context["recentTurns"][0]["userMessage"] == "先推荐一套"
    assert conversation_context["lastRecommendation"]["outfit"]["name"] == "会话测试"
    assert second_prompt["interpretedContext"]["intent"] == "new_outfit"


def _test_storage_dir() -> Path:
    """Builds a workspace-local test storage directory.

    Returns:
        Unique directory under ignored backend storage.
    """
    return Path("storage") / "test_conversations" / str(uuid4())
