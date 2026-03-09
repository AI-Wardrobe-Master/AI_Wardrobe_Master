from typing import List, Optional

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "AI Wardrobe Master"
    API_V1_STR: str = "/api/v1"

    # Database
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

    # Storage
    STORAGE_TYPE: str = "local"  # "s3" or "local"
    LOCAL_STORAGE_PATH: str = "./storage"
    API_BASE_URL: str = "http://localhost:8000"

    # Roboflow Workflow
    ROBOFLOW_API_URL: str = "https://serverless.roboflow.com"
    ROBOFLOW_API_KEY: Optional[str] = None
    ROBOFLOW_WORKSPACE_NAME: Optional[str] = None
    ROBOFLOW_WORKFLOW_ID: Optional[str] = None
    ROBOFLOW_IMAGE_INPUT_NAME: str = "image"
    ROBOFLOW_TIMEOUT_SECONDS: float = 30.0

    # S3 / MinIO
    S3_ENDPOINT: Optional[str] = None
    S3_ACCESS_KEY: Optional[str] = None
    S3_SECRET_KEY: Optional[str] = None
    S3_BUCKET: Optional[str] = None
    S3_REGION: str = "us-east-1"
    S3_PUBLIC_URL: Optional[str] = None

    # Security
    SECRET_KEY: str = "CHANGE-ME-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7

    # Hunyuan3D-2
    HUNYUAN3D_MODEL_PATH: str = "tencent/Hunyuan3D-2"
    HUNYUAN3D_MV_MODEL_PATH: str = "tencent/Hunyuan3D-2mv"
    HUNYUAN3D_LOW_VRAM: bool = False

    # Redis / Celery
    REDIS_URL: str = "redis://localhost:6379/0"

    BACKEND_CORS_ORIGINS: List[str] = ["*"]

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
