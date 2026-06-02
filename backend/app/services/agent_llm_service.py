import json
from typing import Any

import httpx

from app.core.config import settings


class AgentConfigurationError(RuntimeError):
    pass


class AgentLLMError(RuntimeError):
    pass


class OpenAICompatibleChatClient:
    def __init__(self) -> None:
        self.provider_name = settings.LLM_PROVIDER_NAME
        self.model = settings.LLM_MODEL or ""
        self.base_url = (settings.LLM_BASE_URL or "").rstrip("/")
        self.api_key = settings.LLM_API_KEY

    def ensure_configured(self) -> None:
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
        self.ensure_configured()
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "temperature": settings.LLM_TEMPERATURE,
            "stream": False,
        }
        if settings.LLM_USE_RESPONSE_FORMAT:
            payload["response_format"] = {"type": "json_object"}

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

        body = response.json()
        try:
            content = body["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise AgentLLMError("LLM response did not contain message content") from exc
        if isinstance(content, list):
            content = "".join(
                part.get("text", "") if isinstance(part, dict) else str(part)
                for part in content
            )
        return _loads_json_object(str(content))


def _loads_json_object(raw: str) -> dict[str, Any]:
    text = raw.strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            raise AgentLLMError("LLM response was not valid JSON")
        parsed = json.loads(text[start:end + 1])
    if not isinstance(parsed, dict):
        raise AgentLLMError("LLM response JSON must be an object")
    return parsed
