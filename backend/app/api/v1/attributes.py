"""
Attribute options API - Module 2.3.1
返回 style, season, audience 等可配置属性的预定义选项，供前端下拉/芯片选择。
"""
from fastapi import APIRouter

from app.services.clothing_taxonomy import get_clothing_taxonomy

router = APIRouter(prefix="/attributes", tags=["Attributes"])


@router.get("/options")
def get_attribute_options():
    """
    GET /attributes/options
    返回 2.3 可配置属性及 2.1/2.2 属性的预定义选项，供编辑界面使用。
    """
    return {
        "success": True,
        "data": get_clothing_taxonomy(),
    }
