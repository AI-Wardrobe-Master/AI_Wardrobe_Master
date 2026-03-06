"""
AI Classification Service - Module 2.1, 2.2
Integrates: category classification, color detection, pattern recognition.
TODO: 替换 _classify_mock 为实际模型调用。
"""
from pathlib import Path
from typing import List
import logging

from app.schemas.clothing_item import Tag
from app.core.config import settings
from app.core.exceptions import ClassificationError

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# 待定：实际模型接入
# ---------------------------------------------------------------------------
# 可选方案（需调研选型后替换）:
# 1. Hugging Face transformers + 服装分类预训练模型
# 2. TensorFlow Lite / ONNX 轻量模型 (Fashion-MNIST 等)
# 3. 颜色: Pillow + colorthief 或 K-Means
# 4. 图案: 简单 CNN 或规则+纹理特征
# ---------------------------------------------------------------------------
# 依赖项（选型后添加到 requirements.txt）:
# - torch / transformers  (若用 Hugging Face)
# - tensorflow / tflite   (若用 TF)
# - colorthief           (若用主色提取)
# ---------------------------------------------------------------------------

# 预定义类型，与 DATA_MODEL 保持一致
_CATEGORIES = [
    "T_SHIRT", "SHIRT", "BLOUSE", "POLO", "TANK_TOP",
    "SWEATER", "HOODIE", "SWEATSHIRT", "CARDIGAN",
    "JEANS", "TROUSERS", "SHORTS", "SKIRT", "LEGGINGS", "SWEATPANTS",
    "JACKET", "COAT", "BLAZER", "PUFFER", "WIND_BREAKER", "VEST",
    "DRESS", "JUMPSUIT", "ROMPER",
    "SNEAKERS", "BOOTS", "SANDALS", "DRESS_SHOES", "HEELS", "SLIPPERS",
    "HAT", "SCARF", "BELT",
    "OTHER",
]

_COLORS = [
    "black", "white", "gray", "navy", "blue", "red", "green",
    "yellow", "orange", "brown", "pink", "purple", "beige",
]

_PATTERNS = [
    "solid", "striped", "checked", "floral", "geometric",
    "polka_dot", "animal_print", "abstract", "other",
]

_STYLES = ["casual", "formal", "business", "sporty", "bohemian", "vintage", "minimalist", "streetwear", "elegant", "other"]
_SEASONS = ["spring", "summer", "fall", "winter", "all_season"]
_AUDIENCES = ["men", "women", "unisex", "kids", "teen"]


def _load_image_bytes(image_path: str) -> bytes:
    """
    根据 imageUrl 加载图片字节。
    TODO: 与 Module 1 队友确认 - imageUrl 的实际格式（相对路径 / 绝对 URL / 本地路径）及存储服务接口。
    """
    path = image_path
    if path.startswith("/"):
        path = path.lstrip("/")
    if path.startswith("images/"):
        path = path
    full = Path(settings.LOCAL_STORAGE_PATH) / path
    if full.exists():
        return full.read_bytes()
    # TODO: 若使用 S3/MinIO，在此处通过 storage_service 下载
    raise ClassificationError(f"Cannot load image: {image_path}")


def _classify_category(_image_bytes: bytes) -> str:
    """
    服装品类分类。
    TODO: 接入实际分类模型，返回 ClothingType 枚举值。
    """
    # Mock: 返回默认值，便于前后端联调
    return "T_SHIRT"


def _detect_colors(_image_bytes: bytes) -> List[str]:
    """
    主色/次色检测。
    TODO: 使用 colorthief / Pillow+KMeans 等实现。
    """
    return ["blue", "white"]


def _detect_pattern(_image_bytes: bytes) -> str:
    """
    图案识别。
    TODO: 接入图案识别模型或规则。
    """
    return "striped"


def _classify_mock(_image_bytes: bytes) -> List[Tag]:
    """Mock 分类结果，用于开发联调。"""
    return [
        Tag(key="category", value=_classify_category(_image_bytes)),
        Tag(key="color", value="blue"),
        Tag(key="color", value="white"),
        Tag(key="pattern", value=_detect_pattern(_image_bytes)),
        Tag(key="style", value="casual"),
        Tag(key="season", value="summer"),
        Tag(key="audience", value="unisex"),
    ]


class AIService:
    """AI 分类服务：品类、颜色、图案及扩展属性"""

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

        # TODO: 替换为实际模型调用
        tags = _classify_mock(image_bytes)
        return tags
