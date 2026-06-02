"""Verify OpenAI-compatible tool calling for the outfit Agent provider.

This script performs a focused tool-calling round trip:

1. Mock the LangGraph nodes before `outfit_agent_loop`.
2. Reuse the production Agent prompt and production search tool schema.
3. Keep sending simulated tool results back while the model requests tools.
4. Verify that the model can eventually produce a raw JSON outfit
   recommendation that follows the Agent response contract.

It reads provider settings from the existing backend configuration, so secrets
stay in environment variables or `.env` and are never printed.
"""

from __future__ import annotations

import json
import sys
from argparse import ArgumentParser, Namespace
from pathlib import Path
from typing import Any
from uuid import uuid4

import httpx

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.core.config import settings
from app.schemas.agent import OutfitRecommendationRequest
from app.services.clothing_taxonomy import (
    CATEGORY_TO_PREVIEW_GARMENT_CATEGORY,
    get_clothing_taxonomy,
)
from app.services.outfit_agent_service import OutfitRecommendationAgent
from app.services.outfit_agent_tools import (
    OutfitAgentToolExecutor,
    valid_tag_keys,
    valid_tag_values_by_key,
)

MAX_TOOL_ROUNDS = 8


def main() -> int:
    """Runs the provider tool-calling verification.

    Returns:
        Process exit code. `0` means both tool-call and final-answer phases
        succeeded; `1` means configuration, HTTP, or provider behavior failed.
    """
    args = _parse_args()
    missing = _missing_provider_settings()
    if missing:
        print(f"missing_config={','.join(missing)}")
        return 1

    # Mock the LangGraph nodes before `outfit_agent_loop`, then reuse the real
    # Agent loop prompt and tool schema. This keeps provider verification aligned
    # with production without connecting weather, database, or LangGraph runtime.
    taxonomy = get_clothing_taxonomy()
    messages, tools = _mock_outfit_agent_loop_inputs(taxonomy)
    print(f"provider={settings.LLM_PROVIDER_NAME}")
    print(f"model={settings.LLM_MODEL}")

    final_content = ""
    forced_finalization = False
    total_tool_calls = 0
    tool_call_arguments: list[dict[str, Any]] = []
    for round_index in range(1, MAX_TOOL_ROUNDS + 1):
        response = _post_chat_completion(messages=messages, tools=tools)
        assistant_message = _first_assistant_message(response)
        tool_calls = assistant_message.get("tool_calls") or []

        print(f"round_{round_index}_finish_reason={_first_finish_reason(response)}")
        if args.show_model_output:
            print(
                f"round_{round_index}_assistant_message="
                f"{_json_pretty(assistant_message)}"
            )
        print(f"round_{round_index}_tool_call_count={len(tool_calls)}")
        if tool_calls:
            print(f"round_{round_index}_tool_call_names={_tool_call_names(tool_calls)}")
            print(f"round_{round_index}_tool_call_args={_tool_call_args_preview(tool_calls)}")

        # The loop ends when the model stops asking for tools and emits content.
        if not tool_calls:
            final_content = _message_content_as_text(assistant_message.get("content"))
            print(f"final_content_preview={_preview_text(final_content)}")
            break

        total_tool_calls += len(tool_calls)
        messages.append(_assistant_message_for_history(assistant_message))

        # Execute every requested fake tool call and append trusted tool results
        # just like the real LangGraph tool executor will do.
        for tool_call in tool_calls:
            tool_call_arguments.append(_tool_call_arguments(tool_call))
            messages.append(_mock_tool_result_message(tool_call, taxonomy))

    if total_tool_calls == 0:
        print("verification=failed:no_tool_calls")
        return 1

    if not final_content:
        forced_finalization = True
        messages.append(
            {
                "role": "user",
                "content": (
                    "工具调用预算已经用完。不要再调用工具，只能基于上面的工具结果"
                    "返回最终 JSON。"
                ),
            }
        )
        final_response = _post_chat_completion(messages=messages, tools=None)
        final_message = _first_assistant_message(final_response)
        unexpected_tool_calls = final_message.get("tool_calls") or []
        final_content = _message_content_as_text(final_message.get("content"))

        print("forced_finalization=true")
        print(f"forced_finish_reason={_first_finish_reason(final_response)}")
        if args.show_model_output:
            print(f"forced_assistant_message={_json_pretty(final_message)}")
        print(f"forced_tool_call_count={len(unexpected_tool_calls)}")
        print(f"final_content_preview={_preview_text(final_content)}")

        if unexpected_tool_calls:
            print("verification=failed:tool_calls_after_tools_disabled")
            return 1

    try:
        final_json = _loads_json_object(final_content)
    except ValueError as exc:
        print(f"verification=failed:final_not_json:{exc}")
        return 1
    final_contract_error = _validate_final_contract(
        final_content,
        final_json,
        tool_call_arguments,
        taxonomy,
    )
    if final_contract_error:
        print(f"verification=failed:{final_contract_error}")
        return 1

    # The exact outfit quality is not the point of this spike. We only need to
    # confirm that structured output can follow tool execution.
    outfit = final_json.get("outfit")
    if not isinstance(outfit, dict):
        print("verification=failed:missing_outfit_object")
        return 1

    print(f"total_tool_calls={total_tool_calls}")
    print(f"forced_finalization={str(forced_finalization).lower()}")
    print("verification=success")
    return 0


def _parse_args() -> Namespace:
    """Parses command-line options for the verification script.

    Returns:
        Parsed command-line arguments.
    """
    parser = ArgumentParser(
        description="Verify provider tool-calling behavior for the outfit Agent."
    )
    parser.add_argument(
        "--show-model-output",
        action="store_true",
        help=(
            "Print the full assistant message returned by the model on every "
            "round, including content and tool_calls."
        ),
    )
    return parser.parse_args()


def _missing_provider_settings() -> list[str]:
    """Finds missing provider settings without exposing secret values.

    Returns:
        Names of required LLM settings that are not configured.
    """
    missing = []

    # Keep this list in sync with the real Agent LLM client requirements.
    if not settings.LLM_BASE_URL:
        missing.append("LLM_BASE_URL")
    if not settings.LLM_API_KEY:
        missing.append("LLM_API_KEY")
    if not settings.LLM_MODEL:
        missing.append("LLM_MODEL")
    return missing


def _mock_outfit_agent_loop_inputs(
    taxonomy: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Builds real outfit-agent-loop inputs from mocked upstream state.

    Args:
        taxonomy: Backend-controlled clothing taxonomy.

    Returns:
        Pair of OpenAI-compatible messages and tool schemas.
    """
    request = OutfitRecommendationRequest(
        message="明天上海可能下雨，请从我的衣柜里找一套通勤穿搭。",
        city="上海",
        limit=50,
    )
    weather_context = {
        "city": "上海",
        "targetDate": None,
        "weatherType": "rain",
        "source": "mocked_get_weather",
        "note": (
            "This is mocked upstream weather context for provider verification. "
            "Treat the user's rain constraint as weather_type=rain."
        ),
    }

    # `__new__` lets this provider script reuse the real prompt builder without
    # constructing LangGraph or the real LLM client.
    agent_shell = OutfitRecommendationAgent.__new__(OutfitRecommendationAgent)
    messages = agent_shell._agent_loop_messages(
        {
            "request": request,
            "weather_context": weather_context,
            "taxonomy": taxonomy,
        }
    )

    # The executor is used only to expose the production tool schema. Its db and
    # payload builder are never exercised by this script.
    executor = OutfitAgentToolExecutor(
        db=None,
        user_id=uuid4(),
        request=request,
        taxonomy=taxonomy,
        clothing_payload_builder=_unused_clothing_payload_builder,
    )
    return messages, executor.tool_schemas()


def _unused_clothing_payload_builder(db: Any, item: Any) -> dict[str, Any]:
    """Placeholder payload builder for schema-only executor construction.

    Args:
        db: Unused database session placeholder.
        item: Unused clothing item placeholder.

    Returns:
        Empty payload. This function should not be called.
    """
    raise RuntimeError("Provider verification should not execute database tools")


def _post_chat_completion(
    *,
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]] | None,
) -> dict[str, Any]:
    """Calls the configured provider's chat completions endpoint.

    Args:
        messages: OpenAI-compatible chat messages.
        tools: OpenAI-compatible tool schemas, or `None` to disable tools.

    Returns:
        Parsed provider response body.

    Raises:
        httpx.HTTPStatusError: If the provider rejects the request.
    """
    payload = {
        "model": settings.LLM_MODEL,
        "messages": messages,
        "temperature": settings.LLM_TEMPERATURE,
        "stream": False,
    }
    if tools is not None:
        payload["tools"] = tools
        payload["tool_choice"] = "auto"

    # The verification intentionally does not use response_format because some
    # providers reject JSON mode combined with tool calls.
    with httpx.Client(timeout=settings.LLM_TIMEOUT_SECONDS) as client:
        response = client.post(
            f"{settings.LLM_BASE_URL.rstrip('/')}/chat/completions",
            headers={
                "Authorization": f"Bearer {settings.LLM_API_KEY}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
        response.raise_for_status()
        return response.json()


def _first_assistant_message(response_body: dict[str, Any]) -> dict[str, Any]:
    """Extracts the first assistant message from a provider response.

    Args:
        response_body: Parsed chat completion response.

    Returns:
        Assistant message object.
    """
    return response_body["choices"][0]["message"]


def _first_finish_reason(response_body: dict[str, Any]) -> str | None:
    """Extracts the first choice finish reason.

    Args:
        response_body: Parsed chat completion response.

    Returns:
        Finish reason string, or `None` when omitted.
    """
    return response_body["choices"][0].get("finish_reason")


def _assistant_message_for_history(message: dict[str, Any]) -> dict[str, Any]:
    """Normalizes an assistant tool-call message for the next request.

    Args:
        message: Assistant message returned by the provider.

    Returns:
        Message safe to append to the chat history.
    """
    normalized = {
        "role": "assistant",
        "content": message.get("content"),
    }

    # OpenAI-compatible providers expect the exact tool_calls array to be
    # replayed before role=tool results.
    if message.get("tool_calls"):
        normalized["tool_calls"] = message["tool_calls"]
    return normalized


def _mock_tool_result_message(
    tool_call: dict[str, Any],
    taxonomy: dict[str, Any],
) -> dict[str, Any]:
    """Builds a deterministic fake wardrobe result for one tool call.

    Args:
        tool_call: Tool call emitted by the model.
        taxonomy: Backend-controlled clothing taxonomy.

    Returns:
        OpenAI-compatible tool response message.
    """
    arguments = _tool_call_arguments(tool_call)
    validation_error = _validate_tool_arguments(arguments, taxonomy)
    if validation_error:
        result = {
            "status": "failed",
            "errorCode": "INVALID_TOOL_ARGUMENTS",
            "retryable": True,
            "data": {"appliedFilters": arguments},
            "messageForAgent": (
                f"{validation_error} Retry using only the production tool schema. "
                "Do not pass user_id, query, type, or raw weather fields."
            ),
        }
    else:
        items = _mock_items_for_category(arguments.get("category"))
        result = {
            "status": "success",
            "data": {
                "items": items,
                "total": len(items),
                "appliedFilters": arguments,
            },
            "messageForAgent": "Use only these returned wardrobe items.",
        }

    # Tool call ids must match the provider response exactly; otherwise the
    # second request will be rejected by OpenAI-compatible servers.
    return {
        "role": "tool",
        "tool_call_id": tool_call["id"],
        "name": tool_call["function"]["name"],
        "content": json.dumps(result, ensure_ascii=False),
    }


def _tool_call_arguments(tool_call: dict[str, Any]) -> dict[str, Any]:
    """Parses function arguments from one tool call.

    Args:
        tool_call: Tool call emitted by the model.

    Returns:
        Parsed arguments, or an empty dictionary for malformed arguments.
    """
    raw = tool_call.get("function", {}).get("arguments") or "{}"
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _validate_tool_arguments(
    arguments: dict[str, Any],
    taxonomy: dict[str, Any],
) -> str | None:
    """Validates fake search arguments against backend taxonomy rules.

    Args:
        arguments: Tool arguments emitted by the model.
        taxonomy: Backend-controlled clothing taxonomy.

    Returns:
        Error message for the Agent, or `None` when valid.
    """
    allowed_fields = {"category", "source", "tags", "limit"}
    extra_fields = sorted(set(arguments) - allowed_fields)
    if extra_fields:
        return f"Unsupported argument field(s): {', '.join(extra_fields)}."

    valid_keys = set(valid_tag_keys())
    valid_tag_values = valid_tag_values_by_key(taxonomy)
    category = arguments.get("category")
    if category is not None and category not in set(taxonomy["category"]):
        return f"Invalid category: {category}."
    source = arguments.get("source")
    if source is not None and source not in {"OWNED", "IMPORTED"}:
        return f"Invalid source: {source}."

    tags = arguments.get("tags") or []
    if not isinstance(tags, list):
        return "`tags` must be an array."

    # This intentionally mirrors the guardrail the real executor needs: even
    # with schema hints, untrusted model arguments are validated server-side.
    invalid_keys = [
        tag.get("key")
        for tag in tags
        if isinstance(tag, dict) and tag.get("key") not in valid_keys
    ]
    if invalid_keys:
        return f"Invalid tag key(s): {', '.join(map(str, invalid_keys))}."
    invalid_values = []
    for tag in tags:
        if not isinstance(tag, dict):
            continue
        key = tag.get("key")
        value = tag.get("value")
        if key in valid_tag_values and value not in valid_tag_values[key]:
            invalid_values.append(f"{key}={value}")
    if invalid_values:
        return f"Invalid tag value(s): {', '.join(map(str, invalid_values))}."
    return None


def _mock_items_for_category(category: Any) -> list[dict[str, Any]]:
    """Returns deterministic wardrobe items for a requested category.

    Args:
        category: Optional category argument chosen by the model.

    Returns:
        Simulated wardrobe items matching or approximating that category.
    """
    catalog = [
        _mock_item(
            item_id="11111111-1111-1111-1111-111111111111",
            name="浅蓝色通勤衬衫",
            category="SHIRT",
            color="blue",
            material="cotton",
            style="business",
            matched_tags=[
                {"key": "season", "value": "summer"},
                {"key": "weather_type", "value": "rain"},
                {"key": "weather_profile", "value": "summer_rain"},
            ],
        ),
        _mock_item(
            item_id="22222222-2222-2222-2222-222222222222",
            name="深灰色直筒长裤",
            category="TROUSERS",
            color="gray",
            material="polyester",
            style="business",
            matched_tags=[
                {"key": "season", "value": "all_season"},
                {"key": "weather_type", "value": "rain"},
            ],
        ),
        _mock_item(
            item_id="33333333-3333-3333-3333-333333333333",
            name="黑色防滑皮鞋",
            category="DRESS_SHOES",
            color="black",
            material="leather",
            style="formal",
            matched_tags=[
                {"key": "season", "value": "all_season"},
                {"key": "weather_type", "value": "rain"},
            ],
        ),
        _mock_item(
            item_id="44444444-4444-4444-4444-444444444444",
            name="轻薄防风外套",
            category="WIND_BREAKER",
            color="navy",
            material="nylon",
            style="casual",
            matched_tags=[
                {"key": "season", "value": "summer"},
                {"key": "weather_type", "value": "rain"},
                {"key": "weather_profile", "value": "summer_rain"},
            ],
        ),
    ]

    # Broad recall returns the whole small catalog. Category recall lets the
    # model verify individual slots without making the mock brittle.
    if not isinstance(category, str) or not category:
        return catalog
    normalized = category.upper()
    return [item for item in catalog if item["category"] == normalized]


def _mock_item(
    *,
    item_id: str,
    name: str,
    category: str,
    color: str,
    material: str,
    style: str,
    matched_tags: list[dict[str, str]],
) -> dict[str, Any]:
    """Builds a compact mock item matching the real search tool output.

    Args:
        item_id: Stable fake clothing item id.
        name: Display name for the fake item.
        category: Backend clothing category.
        color: Clothing color.
        material: Clothing material.
        style: Clothing style.
        matched_tags: Controlled tags exposed to the model.

    Returns:
        Model-facing search result item payload.
    """
    return {
        "id": item_id,
        "name": name,
        "category": category,
        "previewGarmentCategory": CATEGORY_TO_PREVIEW_GARMENT_CATEGORY.get(category),
        "color": color,
        "material": material,
        "style": style,
        "matchedTags": matched_tags,
    }


def _validate_final_contract(
    final_content: str,
    final_json: dict[str, Any],
    tool_call_arguments: list[dict[str, Any]],
    taxonomy: dict[str, Any],
) -> str | None:
    """Validates model final output against the Agent response contract.

    Args:
        final_content: Raw assistant content.
        final_json: Parsed final JSON object.
        tool_call_arguments: Tool argument objects emitted before finalization.
        taxonomy: Backend-controlled clothing taxonomy.

    Returns:
        Failure suffix for console output, or None when valid.
    """
    stripped = final_content.strip()
    if stripped.startswith("```") or stripped.endswith("```"):
        return "final_wrapped_in_markdown"

    outfit = final_json.get("outfit")
    if not isinstance(outfit, dict):
        return "missing_outfit_object"
    items = outfit.get("items")
    if not isinstance(items, list):
        return "outfit_items_not_array"
    for item in items:
        if isinstance(item, dict) and "reason" in item:
            return "item_level_reason_present"

    if _declares_missing_shoes_without_search(final_json, tool_call_arguments, taxonomy):
        return "missing_shoes_without_shoe_or_broad_search"
    return None


def _declares_missing_shoes_without_search(
    final_json: dict[str, Any],
    tool_call_arguments: list[dict[str, Any]],
    taxonomy: dict[str, Any],
) -> bool:
    """Checks whether the model declared shoes missing without searching shoes.

    Args:
        final_json: Parsed final model response.
        tool_call_arguments: Tool argument objects emitted before finalization.
        taxonomy: Backend-controlled clothing taxonomy.

    Returns:
        True when final output claims shoes are missing before enough search.
    """
    missing_items = final_json.get("missingItems") or []
    if not any(str(item).strip().lower() in {"shoe", "shoes"} for item in missing_items):
        return False
    return not _searched_preview_slot(tool_call_arguments, taxonomy, "SHOES")


def _searched_preview_slot(
    tool_call_arguments: list[dict[str, Any]],
    taxonomy: dict[str, Any],
    preview_slot: str,
) -> bool:
    """Determines whether tool calls searched a preview slot or broad recall.

    Args:
        tool_call_arguments: Tool argument objects emitted by the model.
        taxonomy: Backend-controlled clothing taxonomy.
        preview_slot: Preview slot such as TOP, BOTTOM, or SHOES.

    Returns:
        True if any search was broad or targeted to the requested preview slot.
    """
    mapping = taxonomy.get("previewCategoryMapping", {})
    for arguments in tool_call_arguments:
        category = arguments.get("category")
        if category is None:
            return True
        if mapping.get(category) == preview_slot:
            return True
    return False


def _tool_call_names(tool_calls: list[dict[str, Any]]) -> str:
    """Formats tool call names for console output.

    Args:
        tool_calls: Tool calls emitted by the model.

    Returns:
        Comma-separated function names.
    """
    names = [
        str(call.get("function", {}).get("name", ""))
        for call in tool_calls
    ]
    return ",".join(name for name in names if name)


def _json_pretty(payload: Any) -> str:
    """Serializes a diagnostic payload as readable JSON.

    Args:
        payload: JSON-like object to print.

    Returns:
        Pretty JSON text preserving Chinese characters.
    """
    return json.dumps(payload, ensure_ascii=False, indent=2, default=str)


def _tool_call_args_preview(tool_calls: list[dict[str, Any]]) -> str:
    """Formats tool call arguments for console diagnostics.

    Args:
        tool_calls: Tool calls emitted by the model.

    Returns:
        Compact JSON preview of function arguments.
    """
    args = [
        _tool_call_arguments(call)
        for call in tool_calls
    ]
    return json.dumps(args, ensure_ascii=False)


def _message_content_as_text(content: Any) -> str:
    """Converts provider message content into plain text.

    Args:
        content: Provider-specific message content.

    Returns:
        Text content.
    """
    if isinstance(content, list):
        return "".join(
            part.get("text", "") if isinstance(part, dict) else str(part)
            for part in content
        )
    return "" if content is None else str(content)


def _preview_text(content: Any, *, max_chars: int = 240) -> str:
    """Creates a one-line preview of provider output.

    Args:
        content: Provider message content.
        max_chars: Maximum preview length.

    Returns:
        Truncated single-line text.
    """
    text = _message_content_as_text(content).replace("\n", " ").strip()
    return text[:max_chars]


def _loads_json_object(raw: str) -> dict[str, Any]:
    """Parses a JSON object from model text.

    Args:
        raw: Raw model content.

    Returns:
        Parsed JSON object.

    Raises:
        ValueError: If the content does not contain a JSON object.
    """
    text = raw.strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            raise ValueError("no JSON object found")
        parsed = json.loads(text[start:end + 1])

    # The final Agent response contract is object-shaped.
    if not isinstance(parsed, dict):
        raise ValueError("JSON value is not an object")
    return parsed


if __name__ == "__main__":
    sys.exit(main())
