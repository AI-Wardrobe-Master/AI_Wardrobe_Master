import io
import inspect
import base64
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import Mock
from uuid import uuid4

import pytest
from fastapi import UploadFile
from PIL import Image as PILImage
from starlette.datastructures import Headers

from app.crud import outfit_preview as crud_outfit_preview
from app.models.outfit_preview import OutfitPreviewTask
from app.services import outfit_preview_service


def _png_upload() -> UploadFile:
    image = PILImage.new("RGB", (1, 1), color=(255, 255, 255))
    payload = io.BytesIO()
    image.save(payload, format="PNG")
    payload.seek(0)
    return UploadFile(
        file=payload,
        filename="person.png",
        headers=Headers({"content-type": "image/png"}),
    )


class _FakeBlobService:
    def __init__(self, blob_hash: str = "a" * 64):
        self.blob_hash = blob_hash
        self.addref_calls: list[str] = []

    async def ingest_upload(self, *args, **kwargs):
        return SimpleNamespace(blob_hash=self.blob_hash)

    def addref(self, db, blob_hash: str) -> None:
        self.addref_calls.append(blob_hash)


class _FakeBlobStorage:
    def __init__(self, payload: bytes):
        self.payload = payload

    async def get_bytes(self, blob_hash: str) -> bytes:
        return self.payload


@pytest.mark.asyncio
async def test_blob_to_base64_data_uri_upscales_images_for_dashscope_minimum():
    image = PILImage.new("RGB", (187, 269), color=(255, 255, 255))
    payload = io.BytesIO()
    image.save(payload, format="JPEG")

    data_uri = await outfit_preview_service._blob_to_base64_data_uri(
        _FakeBlobStorage(payload.getvalue()),
        "small-image",
    )

    encoded = data_uri.split(",", 1)[1]
    decoded = base64.b64decode(encoded)
    with PILImage.open(io.BytesIO(decoded)) as resized:
        assert min(resized.size) >= 240
        assert resized.size == (240, 345)


@pytest.mark.asyncio
async def test_create_preview_task_creates_row_with_person_blob_hash(monkeypatch):
    user_id = uuid4()
    clothing_id = uuid4()
    person_blob_hash = "b" * 64
    captured: dict[str, object] = {}

    monkeypatch.setattr(
        outfit_preview_service,
        "get_blob_service",
        lambda: _FakeBlobService(person_blob_hash),
    )
    monkeypatch.setattr(
        outfit_preview_service,
        "resolve_garment_images_for_preview",
        lambda *args, **kwargs: [
            outfit_preview_service.ResolvedPreviewItem(
                clothing_item_id=clothing_id,
                garment_category="TOP",
                garment_image_blob_hash="c" * 64,
                sort_order=0,
            )
        ],
    )

    def fake_create_task(db, **kwargs):
        captured.update(kwargs)
        return OutfitPreviewTask(
            id=uuid4(),
            user_id=kwargs["user_id"],
            person_image_blob_hash=kwargs["person_image_blob_hash"],
            person_view_type=kwargs["person_view_type"],
            garment_categories=kwargs["garment_categories"],
            input_count=len(kwargs["garment_categories"]),
            prompt_template_key=kwargs["prompt_template_key"],
            provider_name=kwargs["provider_name"],
            provider_model=kwargs["provider_model"],
            status="PENDING",
            created_at=datetime.now(timezone.utc),
        )

    monkeypatch.setattr(
        crud_outfit_preview,
        "create_outfit_preview_task",
        fake_create_task,
    )
    monkeypatch.setattr(
        crud_outfit_preview,
        "replace_outfit_preview_task_items",
        lambda db, *, task, items: task,
    )

    db = Mock()
    db.commit = Mock()
    db.refresh = Mock()
    task = await outfit_preview_service.create_preview_task(
        db,
        user_id=user_id,
        person_image=_png_upload(),
        person_view_type="FULL_BODY",
        clothing_item_ids=[clothing_id],
        garment_categories=["TOP"],
    )

    assert task.person_image_blob_hash == person_blob_hash
    assert captured["person_image_blob_hash"] == person_blob_hash


def test_save_outfit_from_preview_task_addrefs_result_blob_before_creating(monkeypatch):
    blob_service = _FakeBlobService()
    user_id = uuid4()
    task = OutfitPreviewTask(
        id=uuid4(),
        user_id=user_id,
        person_image_blob_hash="d" * 64,
        person_view_type="FULL_BODY",
        garment_categories=["TOP"],
        input_count=1,
        prompt_template_key="full_body_top_tryon",
        provider_name=outfit_preview_service.DASHSCOPE_PROVIDER,
        provider_model=outfit_preview_service.DASHSCOPE_MODEL,
        status="COMPLETED",
        preview_image_blob_hash="e" * 64,
        created_at=datetime.now(timezone.utc),
    )
    created_outfit = SimpleNamespace(id=uuid4())

    monkeypatch.setattr(outfit_preview_service, "get_blob_service", lambda: blob_service)
    monkeypatch.setattr(
        crud_outfit_preview,
        "get_owned_outfit_by_preview_task",
        lambda *args, **kwargs: None,
    )
    monkeypatch.setattr(
        crud_outfit_preview,
        "create_outfit_from_preview_task",
        lambda *args, **kwargs: created_outfit,
    )

    result = outfit_preview_service.save_outfit_from_preview_task(Mock(), task=task)

    assert result is created_outfit
    assert blob_service.addref_calls == [task.preview_image_blob_hash]


def test_outfit_preview_provider_model_defaults_match_service_constant():
    signature = inspect.signature(crud_outfit_preview.create_outfit_preview_task)

    assert (
        signature.parameters["provider_model"].default
        == outfit_preview_service.DASHSCOPE_MODEL
    )
    assert (
        OutfitPreviewTask.__table__.c.provider_model.default.arg
        == outfit_preview_service.DASHSCOPE_MODEL
    )
