import json
from typing import Any

import httpx

from app.core.config import settings


class AgentConfigurationError(RuntimeError):
    """Raised when the Agent LLM provider is not configured."""

    pass


class AgentLLMError(RuntimeError):
    """Raised when the Agent LLM provider request or response is invalid."""

    pass


class OpenAICompatibleChatClient:
    """Small OpenAI-compatible chat client used by the outfit Agent.

    The project supports providers such as SiliconFlow and OpenRouter through
    the same `/chat/completions` contract. This adapter keeps that provider
    boundary out of the LangGraph workflow nodes.
    """

    def __init__(self) -> None:
        """Initializes provider settings from backend configuration."""
        self.provider_name = settings.LLM_PROVIDER_NAME
        self.model = settings.LLM_MODEL or ""
        self.base_url = (settings.LLM_BASE_URL or "").rstrip("/")
        self.api_key = settings.LLM_API_KEY

    def ensure_configured(self) -> None:
        """Validates that the required LLM settings are present.

        Raises:
            AgentConfigurationError: If `LLM_BASE_URL`, `LLM_API_KEY`, or
                `LLM_MODEL` is missing.
        """
        # Collect every missing field first so the API can report one clear
        # configuration error instead of failing one variable at a time.
        missing = []
        if not self.base_url:
            missing.append("LLM_BASE_URL")
        if not self.api_key:
            missing.append("LLM_API_KEY")
        if not self.model:
            missing.append("LLM_MODEL")
        if missing:
            raise AgentConfigurationError(
                f"Missing LLM configuration: {', '.join(missing)}"
            )

    def complete_json(self, messages: list[dict[str, str]]) -> dict[str, Any]:
        """Calls the chat completion endpoint and parses a JSON object reply.

        Args:
            messages: OpenAI-compatible chat messages with `role` and `content`.

        Returns:
            A JSON object parsed from the model response content.

        Raises:
            AgentConfigurationError: If required provider settings are missing.
            AgentLLMError: If the HTTP request fails or the model response is
                not a JSON object.
        """
        self.ensure_configured()

        # Build the provider payload in OpenAI-compatible shape. The optional
        # response_format flag is controlled by config because not every
        # compatible provider/model supports JSON mode.
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "temperature": settings.LLM_TEMPERATURE,
            "stream": False,
        }
        if settings.LLM_USE_RESPONSE_FORMAT:
            payload["response_format"] = {"type": "json_object"}

        # Keep transport errors inside an Agent-specific exception so the graph
        # can decide whether to degrade or surface the failure.
        try:
            with httpx.Client(timeout=settings.LLM_TIMEOUT_SECONDS) as client:
                response = client.post(
                    f"{self.base_url}/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
                response.raise_for_status()
        except httpx.HTTPError as exc:
            raise AgentLLMError(f"LLM request failed: {exc}") from exc

        # The OpenAI-compatible response should contain the assistant message at
        # choices[0].message.content. If a provider returns a different shape,
        # fail explicitly instead of passing a malformed value downstream.
        body = response.json()
        try:
            content = body["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise AgentLLMError("LLM response did not contain message content") from exc

        # Some providers can return content as a list of typed parts. Collapse
        # those parts into text before JSON parsing.
        if isinstance(content, list):
            content = "".join(
                part.get("text", "") if isinstance(part, dict) else str(part)
                for part in content
            )
        return _loads_json_object(str(content))


def _loads_json_object(raw: str) -> dict[str, Any]:
    """Parses a model response into a JSON object.

    Args:
        raw: Raw assistant message content returned by the LLM provider.

    Returns:
        Parsed JSON object.

    Raises:
        AgentLLMError: If no JSON object can be parsed from the response.
    """
    # First try strict JSON parsing. This is the expected path when the model
    # follows the system instruction or the provider supports JSON mode.
    text = raw.strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        # Fall back to extracting the outermost object because many chat models
        # still wrap JSON in short natural-language text or markdown fences.
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            raise AgentLLMError("LLM response was not valid JSON")
        parsed = json.loads(text[start:end + 1])

    # The Agent contract expects a JSON object, not an array or scalar, because
    # later nodes read named fields such as outfit and missingItems.
    if not isinstance(parsed, dict):
        raise AgentLLMError("LLM response JSON must be an object")
    return parsed
