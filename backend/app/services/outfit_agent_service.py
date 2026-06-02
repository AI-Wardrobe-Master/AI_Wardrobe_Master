from typing import Any, Literal, TypedDict
from uuid import UUID

from langgraph.graph import END, START, StateGraph
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.models.clothing_item import ClothingItem, Image
from app.models.wardrobe import WardrobeItem
from app.schemas.agent import AgentToolResult, OutfitRecommendationRequest
from app.services.agent_llm_service import (
    AgentConfigurationError,
    AgentLLMError,
    OpenAICompatibleChatClient,
)
from app.services.clothing_taxonomy import (
    CATEGORY_TO_PREVIEW_GARMENT_CATEGORY,
    get_clothing_taxonomy,
)


class OutfitAgentState(TypedDict, total=False):
    db: Session
    user_id: UUID
    request: OutfitRecommendationRequest
    tools: dict[str, AgentToolResult]
    taxonomy: dict[str, Any]
    weather_context: dict[str, Any]
    wardrobe_items: list[dict[str, Any]]
    recommendation: dict[str, Any]
    preview: AgentToolResult
    final: dict[str, Any]


class OutfitRecommendationAgent:
    def __init__(self, llm: OpenAICompatibleChatClient | None = None) -> None:
        self.llm = llm or OpenAICompatibleChatClient()
        self.graph = self._build_graph()

    def run(
        self,
        db: Session,
        *,
        user_id: UUID,
        request: OutfitRecommendationRequest,
    ) -> dict[str, Any]:
        self.llm.ensure_configured()
        final_state = self.graph.invoke(
            {
                "db": db,
                "user_id": user_id,
                "request": request,
                "tools": {},
            }
        )
        return final_state["final"]

    def _build_graph(self):
        workflow = StateGraph(OutfitAgentState)
        workflow.add_node("get_weather", self._get_weather)
        workflow.add_node("get_clothing_taxonomy", self._get_clothing_taxonomy)
        workflow.add_node("search_wardrobe_items", self._search_wardrobe_items)
        workflow.add_node("compose_outfit", self._compose_outfit)
        workflow.add_node("generate_outfit_preview", self._generate_outfit_preview)
        workflow.add_node("final_response", self._final_response)

        workflow.add_edge(START, "get_weather")
        workflow.add_edge("get_weather", "get_clothing_taxonomy")
        workflow.add_edge("get_clothing_taxonomy", "search_wardrobe_items")
        workflow.add_edge("search_wardrobe_items", "compose_outfit")
        workflow.add_conditional_edges(
            "compose_outfit",
            self._preview_branch,
            {
                "preview": "generate_outfit_preview",
                "final": "final_response",
            },
        )
        workflow.add_edge("generate_outfit_preview", "final_response")
        workflow.add_edge("final_response", END)
        return workflow.compile()

    def _get_weather(self, state: OutfitAgentState) -> dict[str, Any]:
        request = state["request"]
        data = {
            "city": request.city,
            "targetDate": request.target_date.isoformat()
            if request.target_date else None,
            "note": (
                "Weather provider is not connected yet. Infer weather only from "
                "the user's message, city, and date if present."
            ),
        }
        result = AgentToolResult(
            status="skipped",
            errorCode="WEATHER_PROVIDER_NOT_CONFIGURED",
            retryable=False,
            messageForAgent=(
                "No external weather facts are available. Do not invent exact "
                "temperature, precipitation, or wind values."
            ),
            messageForUser="暂未接入实时天气服务，本次只根据你的文字需求判断穿搭约束。",
            data=data,
        )
        tools = dict(state.get("tools", {}))
        tools["get_weather"] = result
        return {"tools": tools, "weather_context": data}

    def _get_clothing_taxonomy(self, state: OutfitAgentState) -> dict[str, Any]:
        taxonomy = get_clothing_taxonomy()
        result = AgentToolResult(
            status="success",
            data=taxonomy,
            messageForAgent=(
                "Use category as the clothing type. Use previewCategoryMapping "
                "only when a preview tool is called."
            ),
        )
        tools = dict(state.get("tools", {}))
        tools["get_clothing_taxonomy"] = result
        return {"tools": tools, "taxonomy": taxonomy}

    def _search_wardrobe_items(self, state: OutfitAgentState) -> dict[str, Any]:
        request = state["request"]
        db = state["db"]
        q = db.query(ClothingItem).filter(
            ClothingItem.user_id == state["user_id"],
            ClothingItem.deleted_at.is_(None),
        )
        if request.source is not None:
            q = q.filter(ClothingItem.source == request.source)
        if request.wardrobe_id is not None:
            q = q.join(
                WardrobeItem,
                WardrobeItem.clothing_item_id == ClothingItem.id,
            ).filter(WardrobeItem.wardrobe_id == request.wardrobe_id)
        if request.tags:
            for tag in request.tags:
                q = q.filter(
                    ClothingItem.final_tags.contains(
                        [{"key": tag.key, "value": tag.value}]
                    )
                )
        items = q.order_by(ClothingItem.created_at.desc()).limit(request.limit).all()
        payload = [self._clothing_item_payload(db, item) for item in items]
        status: Literal["success", "failed"] = "success"
        result = AgentToolResult(
            status=status,
            data={"items": payload, "total": len(payload)},
            messageForAgent=(
                "These are the only wardrobe items available to recommend from. "
                "If a needed slot is missing, say so instead of inventing an item."
            ),
        )
        tools = dict(state.get("tools", {}))
        tools["search_wardrobe_items"] = result
        return {"tools": tools, "wardrobe_items": payload}

    def _compose_outfit(self, state: OutfitAgentState) -> dict[str, Any]:
        request = state["request"]
        prompt_payload = {
            "userRequest": request.model_dump(mode="json", by_alias=True),
            "weatherContext": state.get("weather_context", {}),
            "taxonomy": state.get("taxonomy", {}),
            "wardrobeItems": state.get("wardrobe_items", []),
        }
        messages = [
            {
                "role": "system",
                "content": (
                    "You are an outfit recommendation agent for an AI wardrobe app. "
                    "Return only a JSON object. Do not recommend wardrobe items that "
                    "are not present in wardrobeItems. If a category is missing, add "
                    "it to missingItems. The JSON schema is: "
                    "{outfit:{name:string,items:[{clothingItemId:string,slot:string,"
                    "reason:string}]},recommendationReason:string,weatherReason:string,"
                    "preferenceReason:string|null,missingItems:string[],userMessage:string}."
                ),
            },
            {
                "role": "user",
                "content": _json_dumps(prompt_payload),
            },
        ]
        try:
            recommendation = self.llm.complete_json(messages)
        except (AgentConfigurationError, AgentLLMError) as exc:
            recommendation = {
                "outfit": {"name": "推荐生成失败", "items": []},
                "recommendationReason": "LLM provider 调用失败。",
                "weatherReason": None,
                "preferenceReason": None,
                "missingItems": [],
                "userMessage": f"暂时无法生成穿搭推荐：{exc}",
                "error": str(exc),
            }
        recommendation = self._normalize_recommendation(
            recommendation,
            state.get("wardrobe_items", []),
        )
        return {"recommendation": recommendation}

    def _preview_branch(self, state: OutfitAgentState) -> Literal["preview", "final"]:
        return "preview" if state["request"].generate_preview else "final"

    def _generate_outfit_preview(self, state: OutfitAgentState) -> dict[str, Any]:
        result = AgentToolResult(
            status="skipped",
            errorCode="PERSON_IMAGE_REQUIRED",
            retryable=False,
            messageForAgent=(
                "The current outfit preview API requires a person image upload. "
                "This JSON-only agent endpoint cannot create that task yet."
            ),
            messageForUser="当前 Agent 接口还没有上传真人照片参数，所以暂不生成预览图。",
            data={
                "selectedPreviewItems": self._selected_preview_items(
                    state.get("recommendation", {}),
                    state.get("wardrobe_items", []),
                )
            },
        )
        tools = dict(state.get("tools", {}))
        tools["generate_outfit_preview"] = result
        return {"tools": tools, "preview": result}

    def _final_response(self, state: OutfitAgentState) -> dict[str, Any]:
        recommendation = state.get("recommendation", {})
        preview = state.get("preview") or AgentToolResult(
            status="skipped",
            messageForAgent="Preview generation was not requested.",
            messageForUser="本次未请求生成预览图。",
            data={},
        )
        final = {
            "providerName": self.llm.provider_name,
            "providerModel": self.llm.model,
            "outfit": recommendation.get("outfit", {"name": "", "items": []}),
            "recommendationReason": recommendation.get("recommendationReason", ""),
            "weatherReason": recommendation.get("weatherReason"),
            "preferenceReason": recommendation.get("preferenceReason"),
            "missingItems": recommendation.get("missingItems") or [],
            "preview": preview,
            "tools": state.get("tools", {}),
            "rawModelOutput": recommendation,
        }
        return {"final": final}

    def _clothing_item_payload(self, db: Session, item: ClothingItem) -> dict[str, Any]:
        image = (
            db.query(Image)
            .filter(
                Image.clothing_item_id == item.id,
                or_(
                    Image.image_type == "PROCESSED_FRONT",
                    Image.image_type == "ORIGINAL_FRONT",
                    Image.image_type == "PROCESSED_BACK",
                    Image.image_type == "ORIGINAL_BACK",
                ),
            )
            .order_by(Image.image_type.desc())
            .first()
        )
        image_url = None
        if image is not None:
            kind = {
                "PROCESSED_FRONT": "processed-front",
                "ORIGINAL_FRONT": "original-front",
                "PROCESSED_BACK": "processed-back",
                "ORIGINAL_BACK": "original-back",
            }[image.image_type]
            image_url = f"/files/clothing-items/{item.id}/{kind}"
        return {
            "id": str(item.id),
            "name": item.name,
            "category": item.category,
            "previewGarmentCategory": CATEGORY_TO_PREVIEW_GARMENT_CATEGORY.get(
                item.category or ""
            ),
            "color": _first_tag_value(item.final_tags or [], "color"),
            "material": item.material,
            "style": item.style,
            "source": item.source,
            "imageUrl": image_url,
            "finalTags": item.final_tags or [],
            "customTags": item.custom_tags or [],
        }

    def _normalize_recommendation(
        self,
        recommendation: dict[str, Any],
        wardrobe_items: list[dict[str, Any]],
    ) -> dict[str, Any]:
        known_ids = {item["id"] for item in wardrobe_items}
        outfit = recommendation.get("outfit")
        if not isinstance(outfit, dict):
            outfit = {"name": "穿搭推荐", "items": []}
        items = outfit.get("items") if isinstance(outfit.get("items"), list) else []
        outfit["items"] = [
            item for item in items
            if isinstance(item, dict) and item.get("clothingItemId") in known_ids
        ]
        recommendation["outfit"] = outfit
        recommendation.setdefault("recommendationReason", "")
        recommendation.setdefault("weatherReason", None)
        recommendation.setdefault("preferenceReason", None)
        if not isinstance(recommendation.get("missingItems"), list):
            recommendation["missingItems"] = []
        return recommendation

    def _selected_preview_items(
        self,
        recommendation: dict[str, Any],
        wardrobe_items: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        by_id = {item["id"]: item for item in wardrobe_items}
        selected = []
        for item in recommendation.get("outfit", {}).get("items", []):
            clothing_id = item.get("clothingItemId")
            candidate = by_id.get(clothing_id)
            if not candidate or not candidate.get("previewGarmentCategory"):
                continue
            selected.append(
                {
                    "clothingItemId": clothing_id,
                    "garmentCategory": candidate["previewGarmentCategory"],
                }
            )
        return selected


def _first_tag_value(tags: list[dict[str, Any]], key: str) -> str | None:
    for tag in tags:
        if tag.get("key") == key:
            return tag.get("value")
    return None


def _json_dumps(payload: dict[str, Any]) -> str:
    import json

    return json.dumps(payload, ensure_ascii=False, default=str)
