"""
API dependencies - DB session, current user
TODO: 与负责 Auth 的队友确认 - get_current_user 的实现及 JWT 校验方式
"""
from uuid import UUID

from app.db.session import get_db  # noqa: F401 - re-exported for Depends()


# TODO: 占位 - 实际应从 JWT 解析 user_id
def get_current_user_id() -> UUID:
    """
    从 JWT 或 Header 获取当前用户 ID。
    开发阶段可临时使用固定 UUID 或从 Header 读取。
    """
    # 开发占位：返回一个固定测试用户 ID
    # 生产环境必须从 JWT 解析
    from uuid import UUID
    return UUID("00000000-0000-0000-0000-000000000001")
