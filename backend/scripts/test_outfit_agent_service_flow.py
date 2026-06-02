#!/usr/bin/env python3
"""Run a manual end-to-end check for OutfitRecommendationAgent.run()."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.db.session import SessionLocal  # noqa: E402
from app.models.user import User  # noqa: E402
from app.schemas.agent import OutfitRecommendationRequest  # noqa: E402
from app.services.agent_llm_service import OpenAICompatibleChatClient  # noqa: E402
from app.services.conversation_store import JsonlConversationStore  # noqa: E402
from app.services.outfit_agent_service import OutfitRecommendationAgent  # noqa: E402

DEFAULT_EMAIL = "00001@gmail.com"
DEFAULT_CITY = "上海"
DEFAULT_MESSAGE = "后天天气怎么样？我想要一些穿搭建议。"


class TracingOutfitRecommendationAgent(OutfitRecommendationAgent):
    """Outfit Agent variant that prints LangGraph node execution counts."""

    def __init__(self, **kwargs: Any) -> None:
        """Initializes node-count tracing before compiling the graph.

        Args:
            **kwargs: Arguments forwarded to `OutfitRecommendationAgent`.
        """
        self.node_counts: dict[str, int] = {}
        super().__init__(**kwargs)

    def _understand_request(self, state: dict[str, Any]) -> dict[str, Any]:
        """Traces the request-understanding node.

        Args:
            state: Current LangGraph state.

        Returns:
            Node update returned by the production implementation.
        """
        self._mark_node("understand_request")
        return super()._understand_request(state)

    def _get_weather(self, state: dict[str, Any]) -> dict[str, Any]:
        """Traces the weather node.

        Args:
            state: Current LangGraph state.

        Returns:
            Node update returned by the production implementation.
        """
        self._mark_node("get_weather")
        return super()._get_weather(state)

    def _get_clothing_taxonomy(self, state: dict[str, Any]) -> dict[str, Any]:
        """Traces the taxonomy node.

        Args:
            state: Current LangGraph state.

        Returns:
            Node update returned by the production implementation.
        """
        self._mark_node("get_clothing_taxonomy")
        return super()._get_clothing_taxonomy(state)

    def _outfit_agent_loop(self, state: dict[str, Any]) -> dict[str, Any]:
        """Traces the outfit-agent-loop node.

        Args:
            state: Current LangGraph state.

        Returns:
            Node update returned by the production implementation.
        """
        self._mark_node("outfit_agent_loop")
        return super()._outfit_agent_loop(state)

    def _generate_outfit_preview(self, state: dict[str, Any]) -> dict[str, Any]:
        """Traces the preview node.

        Args:
            state: Current LangGraph state.

        Returns:
            Node update returned by the production implementation.
        """
        self._mark_node("generate_outfit_preview")
        return super()._generate_outfit_preview(state)

    def _final_response(self, state: dict[str, Any]) -> dict[str, Any]:
        """Traces the final-response node.

        Args:
            state: Current LangGraph state.

        Returns:
            Node update returned by the production implementation.
        """
        self._mark_node("final_response")
        return super()._final_response(state)

    def _mark_node(self, name: str) -> None:
        """Records and prints one LangGraph node execution.

        Args:
            name: LangGraph node name.
        """
        self.node_counts[name] = self.node_counts.get(name, 0) + 1
        print(f"\n=== graph_node:{name}#{self.node_counts[name]} ===")


class LoggingChatClient(OpenAICompatibleChatClient):
    """OpenAI-compatible chat client that prints every Agent LLM turn."""

    def __init__(self, *, show_messages: bool) -> None:
        """Initializes the logging wrapper around the real provider client.

        Args:
            show_messages: Whether to print the full message list sent to the
                provider on every model call.
        """
        super().__init__()
        self.show_messages = show_messages
        self.call_count = 0

    def complete_message(
        self,
        messages: list[dict[str, Any]],
        *,
        tools: list[dict[str, Any]] | None = None,
        tool_choice: str | dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Calls the provider and prints request/response diagnostics.

        Args:
            messages: OpenAI-compatible chat messages.
            tools: Optional OpenAI-compatible tool schemas.
            tool_choice: Optional tool choice policy.

        Returns:
            Assistant message returned by the configured provider.
        """
        self.call_count += 1
        print(f"\n=== llm_call_{self.call_count}:outfit_agent_loop ===")
        print(f"message_count={len(messages)}")
        print(f"tool_choice={tool_choice}")
        print(f"tool_names={_tool_names(tools)}")

        # Full message logging is intentionally opt-in at construction time
        # because tool results can be large once the wardrobe grows.
        if self.show_messages:
            print("messages=")
            print(_json_pretty(messages))

        assistant_message = super().complete_message(
            messages,
            tools=tools,
            tool_choice=tool_choice,
        )
        print("assistant_message=")
        print(_json_pretty(assistant_message))
        return assistant_message

    def complete_json(self, messages: list[dict[str, Any]]) -> dict[str, Any]:
        """Calls the provider for JSON extraction and prints diagnostics.

        Args:
            messages: OpenAI-compatible chat messages.

        Returns:
            Parsed JSON object returned by the configured provider.
        """
        self.call_count += 1
        print(f"\n=== llm_call_{self.call_count}:understand_request ===")
        print("mode=json_extraction")
        print(f"message_count={len(messages)}")
        print("tool_names=[]")

        # Request-understanding is the first model call in the graph. Printing
        # it lets us verify relative dates such as "明天" before weather lookup.
        if self.show_messages:
            print("messages=")
            print(_json_pretty(messages))

        parsed = super().complete_json(messages)
        print("assistant_json=")
        print(_json_pretty(parsed))
        return parsed


def parse_args() -> argparse.Namespace:
    """Parses command-line options for the manual service-flow script.

    Returns:
        Parsed script arguments.
    """
    parser = argparse.ArgumentParser(
        description="Manually verify OutfitRecommendationAgent.run() end to end."
    )
    parser.add_argument("--email", default=DEFAULT_EMAIL)
    parser.add_argument("--message", default=DEFAULT_MESSAGE)
    parser.add_argument("--city", default=DEFAULT_CITY)
    parser.add_argument("--latitude", type=float, default=None)
    parser.add_argument("--longitude", type=float, default=None)
    parser.add_argument(
        "--target-date",
        type=_parse_date,
        default=None,
        help="Optional ISO date such as 2026-06-03.",
    )
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--generate-preview", action="store_true")
    parser.add_argument(
        "--hide-messages",
        action="store_true",
        help="Hide full LLM request messages and print only assistant outputs.",
    )
    return parser.parse_args()


def get_user_by_email(db: Session, email: str) -> User:
    """Loads an active user row by email.

    Args:
        db: Active SQLAlchemy session.
        email: User email address.

    Returns:
        Active user row.

    Raises:
        RuntimeError: If the email does not map to an active user.
    """
    user = db.query(User).filter(User.email == email, User.is_active.is_(True)).first()
    if user is None:
        raise RuntimeError(f"Active user not found for email: {email}")
    return user


def build_request(args: argparse.Namespace) -> OutfitRecommendationRequest:
    """Builds the public Agent request object from CLI options.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Outfit recommendation request passed into the production Agent service.
    """
    # Only the caller-known request fields are filled here. Weather, taxonomy,
    # wardrobe search, tool cache, and final routing are left to the Agent graph.
    return OutfitRecommendationRequest(
        message=args.message,
        city=args.city,
        latitude=args.latitude,
        longitude=args.longitude,
        targetDate=args.target_date,
        limit=args.limit,
        generatePreview=args.generate_preview,
    )


def run_manual_flow(args: argparse.Namespace) -> dict[str, Any]:
    """Runs OutfitRecommendationAgent.run() with real graph nodes.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Final public Agent payload returned by `run()`.
    """
    with SessionLocal() as db:
        user = get_user_by_email(db, args.email)
        request = build_request(args)
        llm = LoggingChatClient(show_messages=not args.hide_messages)
        agent = TracingOutfitRecommendationAgent(
            llm=llm,
            conversation_store=JsonlConversationStore(),
        )

        print("=== agent_run_input ===")
        print(f"user_email={user.email}")
        print(f"user_id={user.id}")
        print(f"provider={llm.provider_name}")
        print(f"model={llm.model}")
        print("request=")
        print(_json_pretty(request.model_dump(mode="json", by_alias=True)))

        # This is the production service entrypoint. It invokes the compiled
        # LangGraph from START and lets every node populate its own state.
        result = agent.run(db=db, user_id=user.id, request=request)
        print("\n=== graph_node_counts ===")
        print(_json_pretty(agent.node_counts))
        return result


def print_final_result(result: dict[str, Any]) -> None:
    """Prints the final Agent result in a readable diagnostic layout.

    Args:
        result: Final public Agent payload returned by `run()`.
    """
    tools = result.get("tools") or {}
    print("\n=== tool_trace_summary ===")
    for name, tool_result in tools.items():
        print(
            f"{name}: status={_field(tool_result, 'status')} "
            f"errorCode={_field(tool_result, 'errorCode')}"
        )

    print("\n=== final_result ===")
    print(_json_pretty(result))


def _parse_date(raw: str) -> date:
    """Parses an ISO date from the CLI.

    Args:
        raw: Date string in YYYY-MM-DD format.

    Returns:
        Parsed date.
    """
    return date.fromisoformat(raw)


def _tool_names(tools: list[dict[str, Any]] | None) -> list[str]:
    """Extracts tool names from OpenAI-compatible tool schemas.

    Args:
        tools: Tool schemas passed to the provider.

    Returns:
        Ordered tool names.
    """
    if not tools:
        return []
    return [
        str(tool.get("function", {}).get("name") or "")
        for tool in tools
        if tool.get("function")
    ]


def _field(payload: Any, key: str) -> Any:
    """Reads a key from either a dict or a Pydantic model.

    Args:
        payload: Tool result dict or Pydantic model.
        key: Field name or alias to read.

    Returns:
        Field value when present, otherwise None.
    """
    if isinstance(payload, dict):
        return payload.get(key)
    return getattr(payload, key, None) or getattr(payload, _snake_case(key), None)


def _snake_case(value: str) -> str:
    """Converts a lowerCamel alias to snake_case for diagnostics.

    Args:
        value: Field name or alias.

    Returns:
        Snake-case field name.
    """
    chars = []
    for char in value:
        if char.isupper():
            chars.append("_")
            chars.append(char.lower())
        else:
            chars.append(char)
    return "".join(chars).lstrip("_")


def _json_pretty(payload: Any) -> str:
    """Serializes a diagnostic payload as readable JSON.

    Args:
        payload: JSON-like object or Pydantic model.

    Returns:
        Pretty JSON text preserving Chinese characters.
    """
    return json.dumps(payload, ensure_ascii=False, indent=2, default=_json_default)


def _json_default(value: Any) -> Any:
    """Converts non-JSON values used in diagnostics.

    Args:
        value: Value that `json.dumps` cannot serialize directly.

    Returns:
        JSON-serializable representation.
    """
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json", by_alias=True)
    return str(value)


def main() -> int:
    """Runs the manual service-flow verification.

    Returns:
        Process exit code.
    """
    args = parse_args()
    result = run_manual_flow(args)
    print_final_result(result)
    print("\noutfit_agent_service_flow=success")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
