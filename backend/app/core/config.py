import logging
from typing import List, Optional

from pydantic import model_validator
from pydantic_settings import BaseSettings

_DEFAULT_SECRET_KEY_PLACEHOLDER = "CHANGE-ME-in-production"


class Settings(BaseSettings):
    PROJECT_NAME: str = "AI Wardrobe Master"
    API_V1_STR: str = "/api/v1"

    # Deployment environment — set via ENV env var. Accepts 'development'
    # (default), 'production'/'prod', 'staging', 'test', etc.
    ENV: str = "development"

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

    # DashScope outfit preview
    DASHSCOPE_API_KEY: Optional[str] = None

    # S3 / MinIO
    S3_ENDPOINT: Optional[str] = None
    S3_ACCESS_KEY: Optional[str] = None
    S3_SECRET_KEY: Optional[str] = None
    S3_BUCKET: Optional[str] = None
    S3_REGION: str = "us-east-1"
    S3_PUBLIC_URL: Optional[str] = None

    # Security
    SECRET_KEY: str = _DEFAULT_SECRET_KEY_PLACEHOLDER
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7

    # Hunyuan3D-2
    HUNYUAN3D_ENABLED: bool = True
    HUNYUAN3D_MODEL_PATH: str = "tencent/Hunyuan3D-2"
    HUNYUAN3D_MV_MODEL_PATH: str = "tencent/Hunyuan3D-2mv"
    HUNYUAN3D_LOW_VRAM: bool = False
    HUNYUAN3D_SHAPE_SUBFOLDER: str = "hunyuan3d-dit-v2-0"
    HUNYUAN3D_SHAPE_STEPS: int = 50
    HUNYUAN3D_OCTREE_RESOLUTION: int = 384
    HUNYUAN3D_NUM_CHUNKS: int = 8000
    HUNYUAN3D_SKIP_TEXTURE: bool = False

    # Redis / Celery
    REDIS_URL: str = "redis://localhost:6379/0"
    CELERY_TASK_ALWAYS_EAGER: bool = False
    PROCESSING_TASK_LEASE_SECONDS: int = 900
    MAX_UPLOAD_SIZE_BYTES: int = 10 * 1024 * 1024

    # DreamO Service
    DREAMO_SERVICE_URL: str = "http://localhost:9000"
    DREAMO_GENERATE_TIMEOUT_SECONDS: float = 300.0
    DREAMO_DEFAULT_VERSION: str = "v1.1"
    DREAMO_DEFAULT_GUIDANCE_SCALE: float = 4.5
    DREAMO_DEFAULT_STEPS: int = 12
    DREAMO_DEFAULT_WIDTH: int = 1024
    DREAMO_DEFAULT_HEIGHT: int = 1024

    # Selfie preprocessing
    SELFIE_MAX_UPLOAD_SIZE_BYTES: int = 10 * 1024 * 1024
    SELFIE_TARGET_RESOLUTION: int = 1024

    BACKEND_CORS_ORIGINS: List[str] = ["*"]

    @model_validator(mode="after")
    def _reject_default_secret_key_in_prod(self):
        if self.SECRET_KEY == _DEFAULT_SECRET_KEY_PLACEHOLDER:
            env_norm = self.ENV.strip().lower()
            # Match anything starting with 'prod' — 'prod', 'production',
            # 'prod-eu', 'prod_canary', etc. — not just the two literals.
            # Also covers 'staging' / 'stage' so shared-infra envs fail hard.
            is_production_like = (
                env_norm.startswith("prod")
                or env_norm.startswith("stag")
                or env_norm == "live"
            )
            if is_production_like:
                raise ValueError(
                    "SECRET_KEY must be overridden via environment in "
                    f"{self.ENV!r}. Current value is the placeholder default."
                )
            logging.getLogger(__name__).warning(
                "SECRET_KEY is the default placeholder. Override via .env before deploying."
            )
        return self

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
