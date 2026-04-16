from __future__ import annotations

import asyncio
import io
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable
from uuid import UUID

import httpx
from fastapi import HTTPException
from PIL import Image as PILImage
from sqlalchemy.orm import Session

from app.core.config import settings
from app.crud import outfit_preview as crud_outfit_preview
from app.models.clothing_item import ClothingItem
from app.models.outfit_preview import OutfitPreviewTask
from app.services.blob_service import get_blob_service
from app.services.blob_storage import get_blob_storage

logger = logging.getLogger(__name__)

DASHSCOPE_ENDPOINT = (
    "https://dashscope-intl.aliyuncs.com/api/v1"
    "aigc/multimodal-generation/generation"
)
DASHSCOPE_MODEL = "wan2.6-image"
DASHSCOPE_PROVIDER = "DashScope"
MAX_PROVIDER_ATTEMPTS = 3
RETRYABLE_STATUSES = {500, 502, 503, 504}


@dataclass(frozen=True)
class ResolvedPreviewItem:
    clothing_item_id: UUID
    garment_category: str
    garment_image_blob_hash: str
    sort_order: int


class OutfitPreviewProviderError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        code: str | None = None,
        request_id: str | None = None,
        retryable: bool = False,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.request_id = request_id
        self.retryable = retryable


def _absolute_blob_url(blob_storage, blob_hash: str) -> str:
    """Build an absolute file:// URL for a CAS blob (for DashScope API)."""
    path = blob_storage.path_for(blob_hash)
    return Path(path).resolve().as_uri()


def _select_preview_image_blob_hash(item: ClothingItem) -> str | None:
    preferred_types = (
        "PROCESSED_FRONT",
        "ORIGINAL_FRONT",
        "PROCESSED_BACK",
        "ORIGINAL_BACK",
    )
    by_type = {image.image_type: image for image in item.images}
    for image_type in preferred_types:
        image = by_type.get(image_type)
        if image and image.blob_hash:
            return image.blob_hash
    return None


def _normalize_categories(categories: Iterable[str]) -> tuple[str, ...]:
    normalized = tuple(category.strip().upper() for category in categories)
    if len(normalized) != len(set(normalized)):
        raise HTTPException(status_code=422, detail="garmentCategories must be unique")
    invalid = [category for category in normalized if category not in {"TOP", "BOTTOM", "SHOES"}]
    if invalid:
        raise HTTPException(status_code=422, detail="Unsupported garment category")
    return normalized


def select_prompt_template(
    person_view_type: str,
    garment_categories: Iterable[str],
) -> tuple[str, str]:
    categories = frozenset(_normalize_categories(garment_categories))
    view_type = person_view_type.strip().upper()

    prompt_map = {
        ("FULL_BODY", frozenset({"TOP"})): (
            "full_body_top_tryon",
            "根据输入图片生成自然真实的全身上衣试穿预览图",
        ),
        ("FULL_BODY", frozenset({"BOTTOM"})): (
            "full_body_bottom_tryon",
            "根据输入图片生成自然真实的全身下装试穿预览图",
        ),
        ("FULL_BODY", frozenset({"SHOES"})): (
            "full_body_shoes_tryon",
            "根据输入图片生成自然真实的全身鞋子试穿预览图",
        ),
        ("FULL_BODY", frozenset({"TOP", "BOTTOM"})): (
            "full_body_outfit_tryon",
            "根据输入图片生成自然真实的全身穿搭试穿预览图",
        ),
        ("FULL_BODY", frozenset({"TOP", "BOTTOM", "SHOES"})): (
            "full_body_outfit_tryon",
            "根据输入图片生成自然真实的全身穿搭试穿预览图",
        ),
        ("UPPER_BODY", frozenset({"TOP"})): (
            "upper_body_top_tryon",
            "根据输入图片生成自然真实的上半身上衣试穿预览图",
        ),
        ("UPPER_BODY", frozenset({"BOTTOM"})): (
            "upper_body_bottom_tryon",
            "根据输入图片生成自然真实的上半身下装试穿预览图",
        ),
    }

    template = prompt_map.get((view_type, categories))
    if template is None:
        raise HTTPException(
            status_code=422,
            detail="Unsupported personViewType and garmentCategories combination",
        )
    return template


def resolve_garment_images_for_preview(
    db: Session,
    *,
    user_id: UUID,
    clothing_item_ids: list[UUID],
    garment_categories: list[str],
) -> list[ResolvedPreviewItem]:
    if len(clothing_item_ids) != len(garment_categories):
        raise HTTPException(
            status_code=422,
            detail="clothingItemIds and garmentCategories must have the same length",
        )

    normalized_categories = _normalize_categories(garment_categories)
    query = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.user_id == user_id,
            ClothingItem.id.in_(clothing_item_ids),
        )
        .all()
    )
    items_by_id = {item.id: item for item in query}
    missing_ids = [item_id for item_id in clothing_item_ids if item_id not in items_by_id]
    if missing_ids:
        raise HTTPException(status_code=404, detail="Clothing item not found")

    resolved: list[ResolvedPreviewItem] = []
    for sort_order, (item_id, category) in enumerate(zip(clothing_item_ids, normalized_categories)):
        clothing_item = items_by_id[item_id]
        blob_hash = _select_preview_image_blob_hash(clothing_item)
        if blob_hash is None:
            raise HTTPException(
                status_code=422,
                detail=f"Clothing item {clothing_item.id} has no usable image",
            )
        resolved.append(
            ResolvedPreviewItem(
                clothing_item_id=clothing_item.id,
                garment_category=category,
                garment_image_blob_hash=blob_hash,
                sort_order=sort_order,
            )
        )
    return resolved


async def _read_upload_bytes(file) -> bytes:
    payload = file.file.read()
    if not payload:
        raise HTTPException(status_code=422, detail="person_image is empty")
    if len(payload) > settings.MAX_UPLOAD_SIZE_BYTES:
        raise HTTPException(status_code=413, detail="person_image exceeds size limit")
    try:
        with PILImage.open(io.BytesIO(payload)) as image:
            image.verify()
    except Exception as exc:  # pragma: no cover - PIL raises several exception types
        raise HTTPException(status_code=422, detail="person_image must be a valid image") from exc
    return payload


def _prompt_text(template_key: str) -> str:
    prompts = {
        "full_body_top_tryon": "根据输入图片生成自然真实的全身上衣试穿预览图",
        "full_body_bottom_tryon": "根据输入图片生成自然真实的全身下装试穿预览图",
        "full_body_shoes_tryon": "根据输入图片生成自然真实的全身鞋子试穿预览图",
        "full_body_outfit_tryon": "根据输入图片生成自然真实的全身穿搭试穿预览图",
        "upper_body_top_tryon": "根据输入图片生成自然真实的上半身上衣试穿预览图",
        "upper_body_bottom_tryon": "根据输入图片生成自然真实的上半身下装试穿预览图",
    }
    prompt = prompts.get(template_key)
    if prompt is None:
        raise HTTPException(status_code=422, detail="Unsupported prompt template")
    return prompt


def _select_prompt_text(
    person_view_type: str,
    garment_categories: Iterable[str],
    template_key: str,
) -> str:
    selected_key, prompt_text = select_prompt_template(
        person_view_type,
        garment_categories,
    )
    if selected_key != template_key:
        raise OutfitPreviewProviderError(
            "Preview task template key does not match garment categories",
            code="INVALID_TEMPLATE",
        )
    return prompt_text


async def _download_bytes(url: str) -> bytes:
    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
            return response.content
        except httpx.HTTPStatusError as exc:
            status_code = exc.response.status_code
            raise OutfitPreviewProviderError(
                f"Failed to download preview image: HTTP {status_code}",
                code=f"HTTP_{status_code}",
                retryable=status_code in RETRYABLE_STATUSES,
            ) from exc
        except httpx.RequestError as exc:
            raise OutfitPreviewProviderError(
                f"Failed to download preview image: {exc}",
                code="NETWORK_ERROR",
                retryable=True,
            ) from exc


def _parse_dashscope_success(payload: dict) -> tuple[str, str | None]:
    output = payload.get("output")
    if not isinstance(output, dict) or output.get("finished") is not True:
        raise OutfitPreviewProviderError(
            "DashScope response did not finish successfully",
            code="INVALID_RESPONSE",
            request_id=payload.get("request_id"),
        )
    choices = output.get("choices") or []
    if not choices:
        raise OutfitPreviewProviderError(
            "DashScope response did not include any choices",
            code="INVALID_RESPONSE",
            request_id=payload.get("request_id"),
        )
    content = choices[0].get("message", {}).get("content") or []
    for item in content:
        if item.get("type") == "image" and item.get("image"):
            return item["image"], payload.get("request_id")
    raise OutfitPreviewProviderError(
        "DashScope response did not include an image",
        code="INVALID_RESPONSE",
        request_id=payload.get("request_id"),
    )


async def _call_dashscope(
    *,
    person_image_url: str,
    garment_image_urls: list[str],
    prompt_text: str,
) -> tuple[str, str | None]:
    if not settings.DASHSCOPE_API_KEY:
        raise OutfitPreviewProviderError(
            "DASHSCOPE_API_KEY is not configured",
            code="CONFIG_ERROR",
        )

    payload = {
        "model": DASHSCOPE_MODEL,
        "input": {
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"image": person_image_url},
                        *({"image": url} for url in garment_image_urls),
                        {"text": prompt_text},
                    ],
                }
            ]
        },
        "parameters": {
            "size": "2K",
            "n": 1,
            "watermark": False,
            "thinking_mode": True,
        },
    }

    headers = {
        "Authorization": f"Bearer {settings.DASHSCOPE_API_KEY}",
        "Content-Type": "application/json",
    }

    timeout = httpx.Timeout(120.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(DASHSCOPE_ENDPOINT, json=payload, headers=headers)
        request_id: str | None = None
        try:
            data = response.json()
        except ValueError as exc:
            raise OutfitPreviewProviderError(
                "DashScope returned invalid JSON",
                code="INVALID_RESPONSE",
                retryable=response.status_code in RETRYABLE_STATUSES,
            ) from exc

        request_id = data.get("request_id")
        if response.status_code >= 400:
            code = data.get("code") or f"HTTP_{response.status_code}"
            message = data.get("message") or response.text[:500]
            raise OutfitPreviewProviderError(
                message,
                code=code,
                request_id=request_id,
                retryable=response.status_code in RETRYABLE_STATUSES,
            )

        try:
            return _parse_dashscope_success(data)
        except OutfitPreviewProviderError as exc:
            if exc.request_id is None:
                exc.request_id = request_id
            raise


async def create_preview_task(
    db: Session,
    *,
    user_id: UUID,
    person_image,
    person_view_type: str,
    clothing_item_ids: list[UUID],
    garment_categories: list[str],
) -> OutfitPreviewTask:
    blob_service = get_blob_service()
    resolved_items = resolve_garment_images_for_preview(
        db,
        user_id=user_id,
        clothing_item_ids=clothing_item_ids,
        garment_categories=garment_categories,
    )
    prompt_template_key, _ = select_prompt_template(
        person_view_type,
        garment_categories,
    )

    person_bytes = await _read_upload_bytes(person_image)

    task = crud_outfit_preview.create_outfit_preview_task(
        db,
        user_id=user_id,
        person_image_blob_hash="",
        person_view_type=person_view_type.strip().upper(),
        garment_categories=[item.garment_category for item in resolved_items],
        prompt_template_key=prompt_template_key,
        provider_name=DASHSCOPE_PROVIDER,
        provider_model=DASHSCOPE_MODEL,
    )

    try:
        person_blob = await blob_service.ingest_upload(
            db, io.BytesIO(person_bytes),
            claimed_mime_type=person_image.content_type or "image/jpeg",
            max_size=settings.MAX_UPLOAD_SIZE_BYTES,
        )
        task.person_image_blob_hash = person_blob.blob_hash
        crud_outfit_preview.replace_outfit_preview_task_items(
            db,
            task=task,
            items=[
                {
                    "clothing_item_id": item.clothing_item_id,
                    "garment_category": item.garment_category,
                    "sort_order": item.sort_order,
                    "garment_image_blob_hash": item.garment_image_blob_hash,
                }
                for item in resolved_items
            ],
        )
        db.commit()
        db.refresh(task)
    except Exception:
        db.rollback()
        try:
            blob_service.release(db, person_blob.blob_hash)
            db.commit()
        except Exception:
            logger.warning("Failed to release person image blob", exc_info=True)
        raise

    return task


def enqueue_preview_generation(task_id: UUID) -> None:
    from app.tasks import process_outfit_preview

    process_outfit_preview.delay(str(task_id))


def save_outfit_from_preview_task(
    db: Session,
    *,
    task: OutfitPreviewTask,
    name: str | None = None,
):
    if task.status != "COMPLETED" or not task.preview_image_blob_hash:
        raise HTTPException(
            status_code=409,
            detail="Preview task must be completed before saving",
        )
    existing = crud_outfit_preview.get_owned_outfit_by_preview_task(
        db,
        preview_task_id=task.id,
        user_id=task.user_id,
    )
    if existing is not None:
        return existing
    return crud_outfit_preview.create_outfit_from_preview_task(
        db,
        task=task,
        name=name,
    )


async def run_outfit_preview_task(
    task_id: UUID,
    *,
    worker_id: str | None = None,
) -> None:
    from app.db.session import SessionLocal

    db = SessionLocal()
    blob_storage = get_blob_storage()
    blob_service = get_blob_service()
    try:
        task = crud_outfit_preview.get_outfit_preview_task(db, task_id)
        if task is None:
            logger.warning("Outfit preview task %s not found", task_id)
            return
        task = crud_outfit_preview.mark_outfit_preview_processing(
            db,
            task=task,
            worker_id=worker_id,
        )
        if task is None:
            return

        prompt_text = _select_prompt_text(
            task.person_view_type,
            task.garment_categories or [],
            task.prompt_template_key,
        )

        person_image_url = _absolute_blob_url(blob_storage, task.person_image_blob_hash)
        garment_image_urls = [
            _absolute_blob_url(blob_storage, item.garment_image_blob_hash)
            for item in task.items
        ]

        result_image_url = None
        request_id = None
        for attempt in range(1, MAX_PROVIDER_ATTEMPTS + 1):
            try:
                result_image_url, request_id = await _call_dashscope(
                    person_image_url=person_image_url,
                    garment_image_urls=garment_image_urls,
                    prompt_text=prompt_text,
                )
                break
            except OutfitPreviewProviderError as exc:
                if exc.retryable and attempt < MAX_PROVIDER_ATTEMPTS:
                    await asyncio.sleep(2**(attempt - 1))
                    continue
                crud_outfit_preview.mark_outfit_preview_failed(
                    db,
                    task=task,
                    error_code=exc.code,
                    error_message=str(exc),
                    provider_job_id=exc.request_id,
                )
                return
            except httpx.RequestError as exc:
                if attempt < MAX_PROVIDER_ATTEMPTS:
                    await asyncio.sleep(2**(attempt - 1))
                    continue
                crud_outfit_preview.mark_outfit_preview_failed(
                    db,
                    task=task,
                    error_code="NETWORK_ERROR",
                    error_message=str(exc),
                )
                return

        if result_image_url is None:
            crud_outfit_preview.mark_outfit_preview_failed(
                db,
                task=task,
                error_code="INVALID_RESPONSE",
                error_message="DashScope did not return a preview image",
                provider_job_id=request_id,
            )
            return

        result_bytes = await _download_bytes(result_image_url)
        result_blob = await blob_service.ingest_upload(
            db, io.BytesIO(result_bytes),
            claimed_mime_type="image/png",
            max_size=settings.MAX_UPLOAD_SIZE_BYTES * 4,
        )
        crud_outfit_preview.mark_outfit_preview_completed(
            db,
            task=task,
            preview_image_blob_hash=result_blob.blob_hash,
            provider_job_id=request_id,
        )
    except Exception as exc:
        logger.exception("Failed to process outfit preview task %s", task_id)
        try:
            task = crud_outfit_preview.get_outfit_preview_task(db, task_id)
            if task is not None and task.status != "FAILED":
                crud_outfit_preview.mark_outfit_preview_failed(
                    db,
                    task=task,
                    error_code="INTERNAL_ERROR",
                    error_message=str(exc),
                )
        except Exception:
            logger.exception("Failed to mark outfit preview task %s as failed", task_id)
        raise
    finally:
        db.close()
