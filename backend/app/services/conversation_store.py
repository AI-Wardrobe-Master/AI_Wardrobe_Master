"""Local JSONL storage for outfit Agent conversation turns."""

from __future__ import annotations

import json
import re
import threading
from datetime import date, datetime, timezone
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

    def load_user_profile(self, *, user_id: UUID) -> dict[str, Any]:
        """Loads long-term wardrobe preferences for one user."""
        ...

    def merge_user_profile_patch(
        self,
        *,
        user_id: UUID,
        patch: dict[str, Any],
    ) -> dict[str, Any]:
        """Merges a validated userProfile patch into persistent storage."""
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
        profile_record = self._load_user_profile_record(user_id=user_id)
        if not path.exists():
            context = _empty_context(user_id, conversation_id)
            context.update(_profile_context_fields(profile_record))
            return context

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
            **_profile_context_fields(profile_record),
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

    def load_user_profile(self, *, user_id: UUID) -> dict[str, Any]:
        """Loads the user's long-term Agent profile.

        The profile is separate from turn history so the Agent can load only the
        previous turn while still keeping stable wardrobe preferences.
        """
        path = self._path_for_profile(user_id)
        if not path.exists():
            return {}

        with self._lock:
            try:
                parsed = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                return {}
        return _profile_from_record(parsed)

    def merge_user_profile_patch(
        self,
        *,
        user_id: UUID,
        patch: dict[str, Any],
    ) -> dict[str, Any]:
        """Merges a validated userProfile patch and persists the result."""
        with self._lock:
            current_record = self._load_user_profile_record(user_id=user_id)
            merged = merge_user_profile(current_record["profile"], patch)
            today = _today_iso()
            metadata = dict(current_record.get("metadata") or {})
            metadata.setdefault("createdAt", today)
            metadata["updatedAt"] = today
            record = {"profile": merged, "metadata": metadata}
            path = self._path_for_profile(user_id)
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp_path = path.with_suffix(f".{uuid4()}.tmp")
            tmp_path.write_text(
                json.dumps(record, ensure_ascii=False, indent=2, default=str),
                encoding="utf-8",
            )
            tmp_path.replace(path)
        return merged

    def _load_user_profile_record(self, *, user_id: UUID) -> dict[str, Any]:
        """Loads profile plus metadata, accepting legacy profile-only JSON."""
        path = self._path_for_profile(user_id)
        if not path.exists():
            return {"profile": {}, "metadata": {}}

        with self._lock:
            try:
                parsed = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                return {"profile": {}, "metadata": {}}
        return _profile_record_from_payload(parsed)

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

    def _path_for_profile(self, user_id: UUID) -> Path:
        """Builds the JSON path for one user's long-term Agent profile."""
        safe_user_id = re.sub(r"[^a-zA-Z0-9_.-]", "_", str(user_id))
        return self.base_dir / "profiles" / f"{safe_user_id}.json"


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
        "userProfile": {},
        "userProfileMetadata": {},
        "userProfileMemoryNote": None,
    }


def merge_user_profile(
    current: dict[str, Any],
    patch: dict[str, Any],
) -> dict[str, Any]:
    """Merges list-valued profile fields without duplicating values."""
    merged = dict(current) if isinstance(current, dict) else {}
    for key, raw_values in patch.items():
        if not isinstance(raw_values, list):
            continue
        existing = merged.get(key, [])
        values = existing if isinstance(existing, list) else []
        seen = {str(value) for value in values}
        next_values = list(values)
        for raw_value in raw_values:
            if not isinstance(raw_value, str):
                continue
            value = raw_value.strip()
            if not value or value in seen:
                continue
            seen.add(value)
            next_values.append(value)
        if next_values:
            merged[key] = next_values
    return merged


def _profile_context_fields(record: dict[str, Any]) -> dict[str, Any]:
    metadata = dict(record.get("metadata") or {})
    note = _user_profile_memory_note(metadata)
    return {
        "userProfile": dict(record.get("profile") or {}),
        "userProfileMetadata": metadata,
        "userProfileMemoryNote": note,
    }


def _profile_record_from_payload(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"profile": {}, "metadata": {}}

    profile = payload.get("profile")
    metadata = payload.get("metadata")
    if isinstance(profile, dict):
        return {
            "profile": profile,
            "metadata": metadata if isinstance(metadata, dict) else {},
        }

    # Legacy profile files were stored as the profile dictionary itself.
    return {"profile": payload, "metadata": {}}


def _profile_from_record(payload: Any) -> dict[str, Any]:
    return _profile_record_from_payload(payload)["profile"]


def _user_profile_memory_note(metadata: dict[str, Any]) -> str | None:
    created_at = _parse_iso_date(metadata.get("createdAt"))
    if created_at is None:
        return None

    age_days = (_today() - created_at).days
    metadata["ageDays"] = age_days
    if age_days < settings.AGENT_USER_PROFILE_STALE_DAYS:
        return None

    return (
        f"This memory has existed here for {age_days} days. "
        "You need to consider whether this memory is stale."
    )


def _parse_iso_date(value: Any) -> date | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return date.fromisoformat(value[:10])
    except ValueError:
        return None


def _today() -> date:
    return datetime.now(timezone.utc).date()


def _today_iso() -> str:
    return _today().isoformat()


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
