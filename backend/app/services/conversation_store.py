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

    def load_context(self, *, user_id: UUID, limit: int) -> dict[str, Any]:
        """Loads recent conversation context for one user.

        Args:
            user_id: Authenticated user identifier.
            limit: Maximum number of recent turns to return.

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
    ) -> dict[str, Any]:
        """Appends one conversation turn.

        Args:
            user_id: Authenticated user identifier.
            user_message: Current user message.
            assistant_result: Compact assistant result to persist.

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

    def load_context(self, *, user_id: UUID, limit: int) -> dict[str, Any]:
        """Loads recent turns and the last recommendation for one user.

        Args:
            user_id: Authenticated user identifier.
            limit: Maximum number of recent turns to include.

        Returns:
            Prompt-safe conversation context.
        """
        path = self._path_for_user(user_id)
        if not path.exists():
            return _empty_context(user_id)

        # Keep file parsing inside a lock so a local append cannot interleave
        # with a read in the same FastAPI process.
        with self._lock:
            turns = _read_jsonl(path)
        recent_turns = turns[-max(limit, 0):] if limit > 0 else []
        prompt_turns = _prompt_turns(recent_turns)
        last_recommendation = _last_recommendation(prompt_turns)

        return {
            "conversationId": _conversation_id(user_id),
            "recentTurns": prompt_turns,
            "lastRecommendation": last_recommendation,
        }

    def append_turn(
        self,
        *,
        user_id: UUID,
        user_message: str,
        assistant_result: dict[str, Any],
    ) -> dict[str, Any]:
        """Appends one turn to the user's JSONL file.

        Args:
            user_id: Authenticated user identifier.
            user_message: Current user message.
            assistant_result: Compact assistant result to persist.

        Returns:
            Persisted turn payload.
        """
        turn = {
            "conversationId": _conversation_id(user_id),
            "turnId": str(uuid4()),
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "userId": str(user_id),
            "userMessage": user_message,
            "assistantResult": assistant_result,
        }
        path = self._path_for_user(user_id)

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
        "outfit": final_result.get("outfit", {"name": "", "items": []}),
        "recommendationReason": final_result.get("recommendationReason", ""),
        "weatherReason": final_result.get("weatherReason"),
        "preferenceReason": final_result.get("preferenceReason"),
        "missingItems": final_result.get("missingItems") or [],
    }


def _empty_context(user_id: UUID) -> dict[str, Any]:
    """Builds an empty conversation context.

    Args:
        user_id: Authenticated user identifier.

    Returns:
        Empty prompt-safe context.
    """
    return {
        "conversationId": _conversation_id(user_id),
        "recentTurns": [],
        "lastRecommendation": None,
    }


def _conversation_id(user_id: UUID) -> str:
    """Builds the single conversation id used for one user.

    Args:
        user_id: Authenticated user identifier.

    Returns:
        Stable per-user conversation id.
    """
    return f"user:{user_id}"


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
        prompt_turns.append(
            {
                "userMessage": turn.get("userMessage"),
                "assistantResult": turn.get("assistantResult"),
            }
        )
    return prompt_turns
