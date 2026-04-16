import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.db.session import SessionLocal
from app.services.processing_task_service import fail_expired_tasks

logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)

from app.api.v1 import files as files_router
app.include_router(files_router.router, prefix="/files", tags=["Files"])

blobs_dir = Path(settings.LOCAL_STORAGE_PATH) / "blobs"
blobs_dir.mkdir(parents=True, exist_ok=True)


@app.get("/")
def root():
    return {
        "message": "AI Wardrobe Master API",
        "docs": "/docs",
        "health": "/health",
        "api": settings.API_V1_STR,
    }


@app.on_event("startup")
def recover_stale_processing_tasks() -> None:
    db = SessionLocal()
    try:
        recovered = fail_expired_tasks(db)
        if recovered:
            logging.warning("Recovered %s stale processing task(s)", recovered)
    finally:
        db.close()


@app.get("/health")
def health_check():
    return {"status": "ok"}
