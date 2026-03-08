import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_router
from app.core.config import settings

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


@app.get("/")
def root():
    return {
        "message": "AI Wardrobe Master API",
        "docs": "/docs",
        "health": "/health",
        "api": settings.API_V1_STR,
    }


storage_dir = Path(settings.LOCAL_STORAGE_PATH)
storage_dir.mkdir(parents=True, exist_ok=True)
app.mount("/files", StaticFiles(directory=str(storage_dir)), name="files")


@app.get("/health")
def health_check():
    return {"status": "ok"}
