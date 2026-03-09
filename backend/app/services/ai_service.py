"""
AI classification service backed by a Roboflow workflow.
"""
import base64
import json
import logging
from pathlib import Path
from typing import Any, List
from urllib import error, request

from app.core.exceptions import ClassificationError
from app.core.config import settings
from app.schemas.clothing_item import Tag

logger = logging.getLogger(__name__)

SUPPORTED_CATEGORY_VALUES = [
    "dress",
    "hat",
    "longsleeve",
    "outwear",
    "pants",
    "shirt",
    "shoes",
    "shorts",
    "t-shirt",
]

_SUPPORTED_CATEGORY_SET = set(SUPPORTED_CATEGORY_VALUES)
_CATEGORY_ALIASES = {
    "dress": "dress",
    "hat": "hat",
    "long-sleeve": "longsleeve",
    "long_sleeve": "longsleeve",
    "long sleeve": "longsleeve",
    "longsleeve": "longsleeve",
    "outerwear": "outwear",
    "outwear": "outwear",
    "pants": "pants",
    "shirt": "shirt",
    "shoe": "shoes",
    "shoes": "shoes",
    "short": "shorts",
    "shorts": "shorts",
    "t shirt": "t-shirt",
    "t-shirt": "t-shirt",
    "t_shirt": "t-shirt",
    "tee": "t-shirt",
    "tee shirt": "t-shirt",
    "tshirt": "t-shirt",
}
_LABEL_KEYS = {
    "class",
    "class_name",
    "classname",
    "label",
    "name",
    "predicted_class",
    "predictedclass",
    "top",
}


def _load_image_bytes(image_path: str) -> bytes:
    """
    根据 imageUrl 加载图片字节。
    TODO: 与 Module 1 队友确认 - imageUrl 的实际格式（相对路径 / 绝对 URL / 本地路径）及存储服务接口。
    """
    path = image_path
    if path.startswith("/"):
        path = path.lstrip("/")
    if path.startswith("files/"):
        path = path[len("files/") :]
    if path.startswith("images/"):
        path = path
    full = Path(settings.LOCAL_STORAGE_PATH) / path
    if full.exists():
        return full.read_bytes()
    # TODO: 若使用 S3/MinIO，在此处通过 storage_service 下载
    raise ClassificationError(f"Cannot load image: {image_path}")


def _normalize_category_label(raw_label: str) -> str | None:
    normalized = raw_label.strip().lower().replace("_", " ").replace("-", " ")
    normalized = " ".join(normalized.split())
    return _CATEGORY_ALIASES.get(normalized)


def _collect_supported_categories(payload: Any) -> list[str]:
    found: list[str] = []

    def add_label(value: str):
        normalized = _normalize_category_label(value)
        if normalized and normalized not in found:
            found.append(normalized)

    def visit(node: Any):
        if isinstance(node, dict):
            for key, value in node.items():
                key_normalized = key.strip().lower().replace("-", "_")
                if key_normalized in _LABEL_KEYS and isinstance(value, str):
                    add_label(value)
                    continue
                visit(value)
            return
        if isinstance(node, list):
            for item in node:
                visit(item)
            return
        if isinstance(node, str):
            add_label(node)

    visit(payload)
    return found


def _build_workflow_url() -> str:
    missing = [
        name
        for name, value in [
            ("ROBOFLOW_API_KEY", settings.ROBOFLOW_API_KEY),
            ("ROBOFLOW_WORKSPACE_NAME", settings.ROBOFLOW_WORKSPACE_NAME),
            ("ROBOFLOW_WORKFLOW_ID", settings.ROBOFLOW_WORKFLOW_ID),
        ]
        if not value
    ]
    if missing:
        missing_joined = ", ".join(missing)
        raise ClassificationError(
            f"Roboflow configuration missing: {missing_joined}"
        )

    base_url = settings.ROBOFLOW_API_URL.rstrip("/")
    return (
        f"{base_url}/infer/workflows/"
        f"{settings.ROBOFLOW_WORKSPACE_NAME}/{settings.ROBOFLOW_WORKFLOW_ID}"
    )


def _call_roboflow_workflow(image_bytes: bytes) -> Any:
    encoded_image = base64.b64encode(image_bytes).decode("ascii")
    payload = {
        "api_key": settings.ROBOFLOW_API_KEY,
        "inputs": {
            settings.ROBOFLOW_IMAGE_INPUT_NAME: {
                "type": "base64",
                "value": encoded_image,
            }
        },
    }

    body = json.dumps(payload).encode("utf-8")
    workflow_request = request.Request(
        _build_workflow_url(),
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(
        workflow_request,
        timeout=settings.ROBOFLOW_TIMEOUT_SECONDS,
    ) as response:
        return json.load(response)


def _parse_workflow_result(payload: Any) -> List[Tag]:
    categories = _collect_supported_categories(payload)
    if not categories:
        raise ClassificationError(
            "Roboflow workflow returned no supported category. "
            f"Supported values: {', '.join(SUPPORTED_CATEGORY_VALUES)}"
        )

    # 当前流程只落一个主 category，其他属性交给用户手动补充。
    category = categories[0]
    if category not in _SUPPORTED_CATEGORY_SET:
        raise ClassificationError(f"Unsupported category returned: {category}")

    return [Tag(key="category", value=category)]


class AIService:
    """AI 分类服务。"""

    def classify_bytes(self, image_bytes: bytes) -> List[Tag]:
        """
        对图片字节进行分类，返回 predictedTags。
        当前只自动生成模型已支持的 category 标签。
        """
        try:
            payload = _call_roboflow_workflow(image_bytes)
            return _parse_workflow_result(payload)
        except error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")[:500]
            logger.exception("Roboflow workflow request failed: %s", body)
            raise ClassificationError(
                f"Roboflow workflow request failed with status "
                f"{exc.code}: {body}"
            )
        except error.URLError as exc:
            logger.exception("Roboflow workflow network error")
            raise ClassificationError(f"Roboflow workflow network error: {exc}")
        except json.JSONDecodeError as exc:
            logger.exception("Roboflow workflow returned invalid JSON")
            raise ClassificationError(
                f"Roboflow workflow returned invalid JSON: {exc}"
            )
        except Exception as e:
            logger.exception("Failed to classify image bytes")
            raise ClassificationError(str(e))

    def classify(self, image_url: str) -> List[Tag]:
        """
        对单张服装图片进行分类，返回 predictedTags。
        API 不返回置信度。
        """
        try:
            image_bytes = _load_image_bytes(image_url)
        except Exception as e:
            logger.exception("Failed to load image for classification")
            raise ClassificationError(str(e))

        return self.classify_bytes(image_bytes)
