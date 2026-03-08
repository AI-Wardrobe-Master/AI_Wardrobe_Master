"""
Attribute options API - Module 2.3.1
返回 style, season, audience 等可配置属性的预定义选项，供前端下拉/芯片选择。
"""
from fastapi import APIRouter

router = APIRouter(prefix="/attributes", tags=["Attributes"])

# 与 DATA_MODEL 一致
STYLE_OPTIONS = [
    "casual", "formal", "business", "sporty", "bohemian",
    "vintage", "minimalist", "streetwear", "elegant", "other",
]
SEASON_OPTIONS = ["spring", "summer", "fall", "winter", "all_season"]
AUDIENCE_OPTIONS = ["men", "women", "unisex", "kids", "teen"]

# 2.1/2.2 相关，供编辑时参考
CATEGORY_OPTIONS = [
    "T_SHIRT", "SHIRT", "BLOUSE", "POLO", "TANK_TOP",
    "SWEATER", "HOODIE", "SWEATSHIRT", "CARDIGAN",
    "JEANS", "TROUSERS", "SHORTS", "SKIRT", "LEGGINGS", "SWEATPANTS",
    "JACKET", "COAT", "BLAZER", "PUFFER", "WIND_BREAKER", "VEST",
    "DRESS", "JUMPSUIT", "ROMPER",
    "SNEAKERS", "BOOTS", "SANDALS", "DRESS_SHOES", "HEELS", "SLIPPERS",
    "HAT", "SCARF", "BELT",
    "OTHER",
]
COLOR_OPTIONS = [
    "black", "white", "gray", "navy", "blue", "red", "green",
    "yellow", "orange", "brown", "pink", "purple", "beige",
]
PATTERN_OPTIONS = [
    "solid", "striped", "checked", "floral", "geometric",
    "polka_dot", "animal_print", "abstract", "other",
]


@router.get("/options")
def get_attribute_options():
    """
    GET /attributes/options
    返回 2.3 可配置属性及 2.1/2.2 属性的预定义选项，供编辑界面使用。
    """
    return {
        "success": True,
        "data": {
            "style": STYLE_OPTIONS,
            "season": SEASON_OPTIONS,
            "audience": AUDIENCE_OPTIONS,
            "category": CATEGORY_OPTIONS,
            "color": COLOR_OPTIONS,
            "pattern": PATTERN_OPTIONS,
        },
    }
