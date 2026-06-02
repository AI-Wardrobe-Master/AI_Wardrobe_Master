import json
from collections.abc import Callable
from typing import Any
from uuid import UUID

from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.models.clothing_item import ClothingItem
from app.models.wardrobe import WardrobeItem
from app.schemas.agent import (
    AgentToolResult,
    OutfitRecommendationRequest,
    SearchWardrobeItemsToolInput,
)

SEARCH_WARDROBE_ITEMS_TOOL = "search_wardrobe_items"


class OutfitAgentToolExecutor:
    """Executes trusted backend tools requested by the outfit Agent LLM."""

    def __init__(
        self,
        *,
        db: Session,
        user_id: UUID,
        request: OutfitRecommendationRequest,
        taxonomy: dict[str, Any],
        clothing_payload_builder: Callable[[Session, ClothingItem], dict[str, Any]],
    ) -> None:
        """Initializes tool execution with backend-owned request context.

        Args:
            db: Database session used by tools.
            user_id: Authenticated user id injected by the API layer.
            request: Public Agent request containing fixed request filters.
            taxonomy: Backend-controlled clothing taxonomy.
            clothing_payload_builder: Callback that converts ORM rows into
                model-safe payloads.
        """
        self.db = db
        self.user_id = user_id
        self.request = request
        self.taxonomy = taxonomy
        self.clothing_payload_builder = clothing_payload_builder

    def tool_schemas(self) -> list[dict[str, Any]]:
        """Builds OpenAI-compatible tool schemas for the outfit Agent.

        Returns:
            Tool definitions that can be sent to `/chat/completions`.
        """
        # The model receives exact category and tag-key enums. Value enums are
        # supplied in the prompt because JSON schema cannot express key-specific
        # tag value constraints cleanly in this simple list shape.
        return [
            {
                "type": "function",
                "function": {
                    "name": SEARCH_WARDROBE_ITEMS_TOOL,
                    "description": (
                        "Search candidate clothing items from the authenticated "
                        "user's wardrobe. Use this before recommending real "
                        "clothing items. Omit category and tags for broad recall, "
                        "or add backend taxonomy filters when the user request "
                        "requires a specific clothing type, season, weather, "
                        "color, or style. The backend injects user scope and "
                        "request-level filters. Do not pass user_id, query, type, "
                        "or raw weather fields. Category and tag values must "
                        "match the provided taxonomy."
                    ),
                    "parameters": {
                        "type": "object",
                        "additionalProperties": False,
                        "properties": {
                            "category": {
                                "type": "string",
                                "enum": self.taxonomy["category"],
                                "description": (
                                    "Optional clothing category from backend "
                                    "taxonomy, such as SHIRT or TROUSERS."
                                ),
                            },
                            "source": {
                                "type": "string",
                                "enum": ["OWNED", "IMPORTED"],
                                "description": (
                                    "Optional item source. Omit unless the user "
                                    "explicitly asks owned or imported items."
                                ),
                            },
                            "tags": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "additionalProperties": False,
                                    "properties": {
                                        "key": {
                                            "type": "string",
                                            "enum": valid_tag_keys(),
                                        },
                                        "value": {"type": "string"},
                                    },
                                    "required": ["key", "value"],
                                },
                            },
                            "limit": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 50,
                            },
                        },
                    },
                },
            }
        ]

    def execute(
        self,
        *,
        tool_name: str,
        raw_arguments: str | dict[str, Any] | None,
        cache: dict[str, AgentToolResult],
    ) -> AgentToolResult:
        """Executes one LLM-requested tool call with per-run caching.

        Args:
            tool_name: Function name requested by the model.
            raw_arguments: Raw JSON string or parsed argument object.
            cache: Per-run cache keyed by normalized tool call arguments.

        Returns:
            Structured tool result safe to return as a `role=tool` message.
        """
        if tool_name != SEARCH_WARDROBE_ITEMS_TOOL:
            return AgentToolResult(
                status="failed",
                errorCode="UNKNOWN_TOOL",
                retryable=False,
                messageForAgent=f"Unknown tool: {tool_name}.",
            )

        parsed_arguments = _parse_tool_arguments(raw_arguments)
        cache_key = self.cache_key(tool_name, parsed_arguments)
        if cache_key in cache:
            return cache[cache_key]

        # Only successful or structured failed results from the backend executor
        # enter the cache. This prevents duplicate SQL queries and duplicate
        # validation failures within one Agent run.
        result = self._search_wardrobe_items(parsed_arguments)
        cache[cache_key] = result
        return result

    def cache_key(self, tool_name: str, arguments: dict[str, Any]) -> str:
        """Builds a stable cache key for one tool call.

        Args:
            tool_name: Tool function name.
            arguments: Parsed tool arguments.

        Returns:
            JSON string containing user scope, request filters, and arguments.
        """
        # Request-level filters are part of the cache key because the same model
        # arguments can produce different results under another wardrobe/source.
        payload = {
            "tool": tool_name,
            "userId": str(self.user_id),
            "wardrobeId": str(self.request.wardrobe_id)
            if self.request.wardrobe_id else None,
            "requestSource": self.request.source,
            "requestLimit": self.request.limit,
            "requestTags": [
                tag.model_dump()
                for tag in (self.request.tags or [])
            ],
            "arguments": arguments,
        }
        return json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)

    def _search_wardrobe_items(
        self,
        arguments: dict[str, Any],
    ) -> AgentToolResult:
        """Runs the wardrobe search tool after validating model arguments.

        Args:
            arguments: Parsed model-provided tool arguments.

        Returns:
            Structured search result or retryable validation failure.
        """
        try:
            tool_input = SearchWardrobeItemsToolInput.model_validate(arguments)
            self._validate_search_input(tool_input)
        except (ValidationError, ValueError) as exc:
            return AgentToolResult(
                status="failed",
                errorCode="INVALID_TOOL_ARGUMENTS",
                retryable=True,
                messageForAgent=(
                    f"Invalid search_wardrobe_items arguments: {exc}. Retry "
                    "using backend taxonomy category, tag keys, and tag values."
                ),
                data={"appliedFilters": arguments},
            )

        if self.db is None:
            return AgentToolResult(
                status="failed",
                errorCode="DATABASE_SESSION_UNAVAILABLE",
                retryable=False,
                messageForAgent=(
                    "The wardrobe database session is unavailable, so wardrobe "
                    "items cannot be searched in this run. Finish with a "
                    "degraded response and do not invent clothing ids."
                ),
                messageForUser="当前衣柜数据库连接不可用，暂时无法读取衣物。",
                data={"appliedFilters": tool_input.model_dump(mode="json")},
            )

        # Start from the authenticated user's non-deleted clothing items. The
        # model never controls `user_id`, so it cannot cross tenant boundaries.
        q = self.db.query(ClothingItem).filter(
            ClothingItem.user_id == self.user_id,
            ClothingItem.deleted_at.is_(None),
        )

        # Request-level source is fixed by the API caller; model-provided source
        # is allowed only when the request did not already constrain it.
        source = self.request.source or tool_input.source
        if source is not None:
            q = q.filter(ClothingItem.source == source)

        # Wardrobe scoping stays request-owned. The model cannot choose an
        # arbitrary wardrobe id through the tool.
        if self.request.wardrobe_id is not None:
            q = q.join(
                WardrobeItem,
                WardrobeItem.clothing_item_id == ClothingItem.id,
            ).filter(WardrobeItem.wardrobe_id == self.request.wardrobe_id)

        if tool_input.category is not None:
            q = q.filter(ClothingItem.category == tool_input.category)

        # Apply API request tags first, then model-selected tags. All values are
        # structured final_tags filters, never free-text search.
        for tag in self.request.tags or []:
            q = q.filter(
                ClothingItem.final_tags.contains(
                    [{"key": tag.key, "value": tag.value}]
                )
            )
        for tag in tool_input.tags or []:
            q = q.filter(
                ClothingItem.final_tags.contains(
                    [{"key": tag.key, "value": tag.value}]
                )
            )

        limit = min(tool_input.limit, self.request.limit)
        items = q.order_by(ClothingItem.created_at.desc()).limit(limit).all()
        payload = [
            self._model_item_payload(item, tool_input)
            for item in items
        ]

        return AgentToolResult(
            status="success",
            data={
                "items": payload,
                "total": len(payload),
                "appliedFilters": tool_input.model_dump(mode="json"),
            },
            messageForAgent=(
                "Use only these returned wardrobe items. If a needed slot is "
                "missing, call the tool again with a different or broader "
                "category/tags filter, or report the missing item."
            ),
        )

    def _model_item_payload(
        self,
        item: ClothingItem,
        tool_input: SearchWardrobeItemsToolInput,
    ) -> dict[str, Any]:
        """Builds the compact item payload returned to the model.

        Args:
            item: Clothing item ORM row.
            tool_input: Validated tool input for this search call.

        Returns:
            Model-facing clothing item summary with controlled matched tags.
        """
        # Start from the shared item summary, then add only the tags that help
        # the model explain this search result.
        payload = self.clothing_payload_builder(self.db, item)
        payload["matchedTags"] = _select_matched_tags(
            item.final_tags or [],
            tool_input,
            self.request,
        )
        return payload

    def _validate_search_input(
        self,
        tool_input: SearchWardrobeItemsToolInput,
    ) -> None:
        """Validates parsed search input against backend taxonomy.

        Args:
            tool_input: Parsed search tool input.

        Raises:
            ValueError: If category, tag key, or tag value is not allowed.
        """
        if (
            tool_input.category is not None
            and tool_input.category not in set(self.taxonomy["category"])
        ):
            raise ValueError(f"invalid category: {tool_input.category}")

        valid_values = valid_tag_values_by_key(self.taxonomy)
        for tag in tool_input.tags or []:
            if tag.key not in valid_values:
                raise ValueError(f"invalid tag key: {tag.key}")
            if tag.value not in valid_values[tag.key]:
                raise ValueError(f"invalid tag value: {tag.key}={tag.value}")


def valid_tag_keys() -> list[str]:
    """Returns final tag keys accepted by Agent wardrobe search.

    Returns:
        Backend-approved final tag keys.
    """
    return [
        "season",
        "weather_type",
        "weather_profile",
        "color",
        "style",
        "pattern",
        "audience",
    ]


def valid_tag_values_by_key(taxonomy: dict[str, Any]) -> dict[str, list[str]]:
    """Builds valid tag values grouped by accepted final tag key.

    Args:
        taxonomy: Backend-controlled clothing taxonomy.

    Returns:
        Mapping from tag key to accepted values.
    """
    return {
        "season": taxonomy["season"],
        "weather_type": taxonomy["weatherTypes"],
        "weather_profile": taxonomy["weatherProfiles"],
        "color": taxonomy["color"],
        "style": taxonomy["style"],
        "pattern": taxonomy["pattern"],
        "audience": taxonomy["audience"],
    }


def _select_matched_tags(
    final_tags: list[dict[str, Any]],
    tool_input: SearchWardrobeItemsToolInput,
    request: OutfitRecommendationRequest,
) -> list[dict[str, str]]:
    """Selects controlled tags worth returning in a search result.

    Args:
        final_tags: Clothing item final tags from the database.
        tool_input: Validated model-provided search filters.
        request: Outer API request filters.

    Returns:
        Controlled tag dictionaries relevant to this search result.
    """
    requested_keys = {
        tag.key
        for tag in [
            *(request.tags or []),
            *(tool_input.tags or []),
        ]
    }
    tag_keys = requested_keys or set(valid_tag_keys())

    # Only expose backend-approved tag keys. Internal custom tags and full raw
    # final_tags stay out of the LLM tool result.
    allowed_keys = set(valid_tag_keys())
    selected = []
    seen = set()
    for tag in final_tags:
        key = tag.get("key") if isinstance(tag, dict) else None
        value = tag.get("value") if isinstance(tag, dict) else None
        marker = (key, value)
        if (
            key in tag_keys
            and key in allowed_keys
            and isinstance(value, str)
            and marker not in seen
        ):
            seen.add(marker)
            selected.append({"key": key, "value": value})
    return selected


def _parse_tool_arguments(raw_arguments: str | dict[str, Any] | None) -> dict[str, Any]:
    """Parses provider tool-call arguments into a dictionary.

    Args:
        raw_arguments: Tool arguments from the provider response.

    Returns:
        Parsed dictionary. Malformed arguments return a sentinel dictionary so
        Pydantic validation can produce a structured tool failure.
    """
    if raw_arguments is None:
        return {}
    if isinstance(raw_arguments, dict):
        return raw_arguments
    try:
        parsed = json.loads(raw_arguments)
    except json.JSONDecodeError:
        return {"__invalid_json__": raw_arguments}
    return parsed if isinstance(parsed, dict) else {"__invalid_json__": raw_arguments}
