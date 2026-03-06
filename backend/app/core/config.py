"""
Configuration management
"""
from typing import List
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # API
    API_V1_STR: str = "/api/v1"
    PROJECT_NAME: str = "AI Wardrobe Master"

    # Database - TODO: 与队友确认数据库连接字符串
    POSTGRES_SERVER: str = "localhost"
    POSTGRES_USER: str = "wardrobe_user"
    POSTGRES_PASSWORD: str = "wardrobe_pass"
    POSTGRES_DB: str = "wardrobe_db"
    POSTGRES_PORT: str = "5432"

    @property
    def DATABASE_URL(self) -> str:
        return (
            f"postgresql://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_SERVER}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    # Local file storage base path (for imageUrl resolution)
    # TODO: 与 Module 1 队友确认图片存储根路径
    LOCAL_STORAGE_PATH: str = "./storage"
    API_BASE_URL: str = "http://localhost:8000"

    # CORS
    BACKEND_CORS_ORIGINS: List[str] = ["*"]

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
