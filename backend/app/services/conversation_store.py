"""Local JSONL storage for outfit Agent conversation turns."""

from __future__ import annotations

import json
import re
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol
from uuid import UUID, uuid4

from app.core.config import settings


class ConversationStore(Protocol):
    """Storage interface for loading and appending Agent conversation turns."""

    def load_context(
        self,
        *,
        user_id: UUID,
        limit: int,
        conversation_id: str | None = None,
    ) -> dict[str, Any]:
        """Loads recent conversation context for one user.

        Args:
            user_id: Authenticated user identifier.
            limit: Maximum number of recent turns to return.
            conversation_id: Optional product conversation identifier.

        Returns:
            Compact conversation context for the Agent prompt.
        """
        ...

    def append_turn(
        self,
        *,
        user_id: UUID,
        user_message: str,
        assistant_result: dict[str, Any],
        conversation_id: str | None = None,
    ) -> dict[str, Any]:
        """Appends one conversation turn.

        Args:
            user_id: Authenticated user identifier.
            user_message: Current user message.
            assistant_result: Compact assistant result to persist.
            conversation_id: Optional product conversation identifier.

        Returns:
            Persisted turn payload.
        """
        ...


class JsonlConversationStore:
    """Per-user JSONL conversation store for local MVP deployments."""

    def __init__(self, base_dir: str | Path | None = None) -> None:
        """Initializes the JSONL store.

        Args:
            base_dir: Optional storage directory override. When omitted, the
                path comes from backend settings.
        """
        self.base_dir = Path(base_dir or settings.AGENT_CONVERSATION_STORAGE_PATH)
        self._lock = threading.RLock()

    def load_context(
        self,
        *,
        user_id: UUID,
        limit: int,
        conversation_id: str | None = None,
    ) -> dict[str, Any]:
        """Loads recent turns and the last recommendation for one user.

        Args:
            user_id: Authenticated user identifier.
            limit: Maximum number of recent turns to include.
            conversation_id: Optional product conversation identifier.

        Returns:
            Prompt-safe conversation context.
        """
        path = self._path_for_conversation(user_id, conversation_id)
        if not path.exists():
            return _empty_context(user_id, conversation_id)

        # Keep file parsing inside a lock so a local append cannot interleave
        # with a read in the same FastAPI process.
        with self._lock:
            turns = _read_jsonl(path)
        recent_turns = turns[-max(limit, 0):] if limit > 0 else []
        prompt_turns = _prompt_turns(recent_turns)
        last_recommendation = _last_recommendation(prompt_turns)

        return {
            "conversationId": _conversation_id(user_id, conversation_id),
            "recentTurns": prompt_turns,
            "lastRecommendation": last_recommendation,
        }

    def append_turn(
        self,
        *,
        user_id: UUID,
        user_message: str,
        assistant_result: dict[str, Any],
        conversation_id: str | None = None,
    ) -> dict[str, Any]:
        """Appends one turn to the user's JSONL file.

        Args:
            user_id: Authenticated user identifier.
            user_message: Current user message.
            assistant_result: Compact assistant result to persist.
            conversation_id: Optional product conversation identifier.

        Returns:
            Persisted turn payload.
        """
        turn = {
            "conversationId": _conversation_id(user_id, conversation_id),
            "turnId": str(uuid4()),
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "userId": str(user_id),
            "userMessage": user_message,
            "assistantResult": assistant_result,
        }
        path = self._path_for_conversation(user_id, conversation_id)

        # JSONL append keeps each turn inspectable while avoiding a read-modify-
        # write cycle for the whole conversation history.
        with self._lock:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8") as file:
                file.write(json.dumps(turn, ensure_ascii=False, default=str))
                file.write("\n")
        return turn

    def _path_for_user(self, user_id: UUID) -> Path:
        """Builds the JSONL path for one user.

        Args:
            user_id: Authenticated user identifier.

        Returns:
            Absolute or relative path to the user's conversation file.
        """
        safe_user_id = re.sub(r"[^a-zA-Z0-9_.-]", "_", str(user_id))
        return self.base_dir / f"{safe_user_id}.jsonl"

    def _path_for_conversation(
        self,
        user_id: UUID,
        conversation_id: str | None,
    ) -> Path:
        """Builds the JSONL path for a user's conversation.

        Args:
            user_id: Authenticated user identifier.
            conversation_id: Optional product conversation identifier.

        Returns:
            Path to the default user conversation or a named chat conversation.
        """
        if conversation_id is None or conversation_id == _conversation_id(user_id):
            return self._path_for_user(user_id)

        safe_user_id = re.sub(r"[^a-zA-Z0-9_.-]", "_", str(user_id))
        safe_conversation_id = re.sub(
            r"[^a-zA-Z0-9_.-]",
            "_",
            conversation_id,
        )
        return self.base_dir / safe_user_id / f"{safe_conversation_id}.jsonl"


def compact_assistant_result(final_result: dict[str, Any]) -> dict[str, Any]:
    """Builds the compact assistant result saved in conversation history.

    Args:
        final_result: Public Agent result returned by the service.

    Returns:
        Smaller payload containing only fields useful for later turns.
    """
    # Avoid saving tools and raw provider traces by default. The next prompt only
    # needs the outfit and high-level reasons to support revision requests.
    return {
        "providerName": final_result.get("providerName"),
        "providerModel": final_result.get("providerModel"),
        "assistantMessage": _assistant_message_from_result(final_result),
        "outfit": final_result.get("outfit", {"name": "", "items": []}),
        "recommendationReason": final_result.get("recommendationReason", ""),
        "weatherReason": final_result.get("weatherReason"),
        "preferenceReason": final_result.get("preferenceReason"),
        "missingItems": final_result.get("missingItems") or [],
    }


def _empty_context(
    user_id: UUID,
    conversation_id: str | None = None,
) -> dict[str, Any]:
    """Builds an empty conversation context.

    Args:
        user_id: Authenticated user identifier.
        conversation_id: Optional product conversation identifier.

    Returns:
        Empty prompt-safe context.
    """
    return {
        "conversationId": _conversation_id(user_id, conversation_id),
        "recentTurns": [],
        "lastRecommendation": None,
    }


def _conversation_id(user_id: UUID, conversation_id: str | None = None) -> str:
    """Builds the single conversation id used for one user.

    Args:
        user_id: Authenticated user identifier.
        conversation_id: Optional product conversation identifier.

    Returns:
        Stable per-user conversation id.
    """
    return conversation_id or f"user:{user_id}"


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    """Reads valid JSON objects from a JSONL file.

    Args:
        path: Conversation file path.

    Returns:
        Parsed turn objects. Malformed lines are ignored.
    """
    turns: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            turns.append(parsed)
    return turns


def _last_recommendation(turns: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Finds the most recent assistant result in a turn list.

    Args:
        turns: Recent conversation turns.

    Returns:
        Latest assistant result, or None when absent.
    """
    for turn in reversed(turns):
        result = turn.get("assistantResult")
        if isinstance(result, dict):
            return result
    return None


def _prompt_turns(turns: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Compacts stored turns for model prompt context.

    Args:
        turns: Stored JSONL turn objects.

    Returns:
        Prompt-safe turns containing only user text and assistant result.
    """
    prompt_turns = []
    for turn in turns:
        assistant_result = turn.get("assistantResult")
        prompt_turns.append(
            {
                "userMessage": turn.get("userMessage"),
                "assistantMessage": _assistant_message_from_result(
                    assistant_result,
                ),
                "assistantResult": assistant_result,
            }
        )
    return prompt_turns


def _assistant_message_from_result(result: dict[str, Any] | None) -> str | None:
    """Extracts a displayable assistant message from a compact result."""
    if not isinstance(result, dict):
        return None

    direct = result.get("assistantMessage")
    if isinstance(direct, str) and direct.strip():
        return direct.strip()

    raw = result.get("rawModelOutput")
    if isinstance(raw, dict):
        raw_message = raw.get("assistantMessage")
        if isinstance(raw_message, str) and raw_message.strip():
            return raw_message.strip()

    reason = result.get("recommendationReason")
    if isinstance(reason, str) and reason.strip():
        return reason.strip()
    return None
