"""
Attribute options API - Module 2.3.1
返回 style, season, audience 等可配置属性的预定义选项，供前端下拉/芯片选择。
"""
from fastapi import APIRouter

from app.services.clothing_taxonomy import get_clothing_taxonomy

router = APIRouter(prefix="/attributes", tags=["Attributes"])


@router.get("/options")
def get_attribute_options():
    """Returns controlled clothing attribute options.

    Returns:
        API envelope containing style, season, category, weather, and preview
        mapping taxonomy values.
    """
    # Delegate to the shared taxonomy service so the UI and Agent expose the
    # same controlled vocabularies.
    return {
        "success": True,
        "data": get_clothing_taxonomy(),
    }
