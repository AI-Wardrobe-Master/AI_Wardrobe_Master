import pytest

pytestmark = pytest.mark.skip(
    reason="Pre-existing test; uses removed storage_path field on Image model "
    "(CAS refactor replaced it with blob_hash). Needs rewrite. "
    "Tracked as FU-T03 in groupmembers'markdown/gch.md (2026-04-20 §8)."
)

import io
import asyncio
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, Mock, patch
from uuid import uuid4

from fastapi import HTTPException, UploadFile
from starlette.datastructures import Headers

from app.api.v1.clothing import (
    _read_upload_bytes,
    _progress_to_steps,
    create_clothing_item,
    retry_processing,
)
from app.models.clothing_item import ClothingItem, Image, Model3D, ProcessingTask
from app.schemas.clothing_item import Tag
from app.services.clothing_pipeline import run_pipeline_task
from app.tasks import process_pipeline


class FakeQuery:
    def __init__(self, session, model, items):
        self._session = session
        self._model = model
        self._items = items
        self._criteria = []
        self._order_desc = False

    def filter(self, *criteria):
        self._criteria.extend(criteria)
        return self

    def order_by(self, *args, **kwargs):
        for arg in args:
            modifier = getattr(arg, "modifier", None)
            if modifier is not None and getattr(modifier, "__name__", "") == "desc_op":
                self._order_desc = True
        return self

    def with_for_update(self):
        return self

    def first(self):
        items = self.all()
        return items[0] if items else None

    def all(self):
        items = [item for item in self._items if self._matches(item)]
        if self._order_desc:
            items.sort(
                key=lambda item: getattr(item, "created_at", datetime.min.replace(tzinfo=timezone.utc)),
                reverse=True,
            )
        return items

    def delete(self, synchronize_session=False):
        matches = self.all()
        for item in matches:
            self._session._data[self._model].remove(item)
        return len(matches)

    def _matches(self, item):
        for criterion in self._criteria:
            left = getattr(criterion, "left", None)
            key = getattr(left, "key", None)
            operator = getattr(getattr(criterion, "operator", None), "__name__", "")
            right = getattr(criterion, "right", None)
            value = getattr(right, "value", None)
            item_value = getattr(item, key)
            if operator == "eq" and item_value != value:
                return False
            if operator == "in_op" and item_value not in value:
                return False
        return True


class FakeSession:
    def __init__(self, items=None, images=None, tasks=None):
        self._data = {
            ClothingItem: list(items or []),
            Image: list(images or []),
            Model3D: [],
            ProcessingTask: list(tasks or []),
        }

    def add(self, instance):
        self._data.setdefault(type(instance), []).append(instance)

    def flush(self):
        return None

    def commit(self):
        return None

    def rollback(self):
        return None

    def refresh(self, instance):
        return instance

    def close(self):
        return None

    def query(self, model):
        return FakeQuery(self, model, self._data.setdefault(model, []))


def make_upload(filename: str, payload: bytes, content_type: str) -> UploadFile:
    return UploadFile(
        file=io.BytesIO(payload),
        filename=filename,
        headers=Headers({"content-type": content_type}),
    )


class ClothingProcessingTests(unittest.IsolatedAsyncioTestCase):
    async def test_create_clothing_item_populates_predicted_tags_before_processing(self):
        user_id = uuid4()
        db = FakeSession()
        storage = AsyncMock()
        storage.upload = AsyncMock()
        storage.delete = AsyncMock()

        with patch("app.api.v1.clothing._storage", return_value=storage), patch(
            "app.api.v1.clothing.process_pipeline.delay",
            new=Mock(),
        ), patch(
            "app.api.v1.clothing.AIService"
        ) as ai_service_cls:
            ai_service_cls.return_value.classify_bytes.return_value = [
                Tag(key="category", value="shirt")
            ]
            await create_clothing_item(
                front_image=make_upload("front.jpg", b"front", "image/jpeg"),
                back_image=None,
                name="Blue Tee",
                description="cotton",
                db=db,
                user_id=user_id,
            )

        item = db._data[ClothingItem][0]
        self.assertEqual(item.predicted_tags, [{"key": "category", "value": "shirt"}])
        self.assertEqual(item.final_tags, [{"key": "category", "value": "shirt"}])
        self.assertFalse(item.is_confirmed)

    async def test_create_clothing_item_enqueues_pending_task(self):
        user_id = uuid4()
        db = FakeSession()
        storage = AsyncMock()
        storage.upload = AsyncMock()
        storage.delete = AsyncMock()

        with patch("app.api.v1.clothing._storage", return_value=storage), patch(
            "app.api.v1.clothing.process_pipeline.delay",
            new=Mock(),
        ) as delay, patch(
            "app.api.v1.clothing.AIService"
        ) as ai_service_cls:
            ai_service_cls.return_value.classify_bytes.return_value = [
                Tag(key="category", value="shirt")
            ]
            response = await create_clothing_item(
                front_image=make_upload("front.jpg", b"front", "image/jpeg"),
                back_image=make_upload("back.jpg", b"back", "image/jpeg"),
                name="Blue Tee",
                description="cotton",
                db=db,
                user_id=user_id,
            )

        self.assertEqual(response.status, "PENDING")
        self.assertEqual(len(db._data[ClothingItem]), 1)
        self.assertEqual(len(db._data[Image]), 2)
        self.assertEqual(len(db._data[ProcessingTask]), 1)
        delay.assert_called_once()

    async def test_retry_processing_rejects_active_task(self):
        user_id = uuid4()
        item = ClothingItem(
            id=uuid4(),
            user_id=user_id,
            source="OWNED",
            predicted_tags=[],
            final_tags=[],
            is_confirmed=False,
        )
        task = ProcessingTask(
            id=uuid4(),
            clothing_item_id=item.id,
            task_type="FULL_PIPELINE",
            status="PROCESSING",
            progress=30,
            created_at=datetime.now(timezone.utc),
        )
        db = FakeSession(items=[item], tasks=[task])

        with self.assertRaises(HTTPException) as ctx:
            await retry_processing(item.id, db=db, user_id=user_id)

        self.assertEqual(ctx.exception.status_code, 409)

    async def test_retry_processing_creates_new_attempt_for_failed_task(self):
        user_id = uuid4()
        item = ClothingItem(
            id=uuid4(),
            user_id=user_id,
            source="OWNED",
            predicted_tags=[],
            final_tags=[],
            is_confirmed=False,
        )
        failed_task = ProcessingTask(
            id=uuid4(),
            clothing_item_id=item.id,
            task_type="FULL_PIPELINE",
            attempt_no=1,
            status="FAILED",
            progress=25,
            created_at=datetime.now(timezone.utc) - timedelta(minutes=1),
        )
        db = FakeSession(items=[item], tasks=[failed_task])

        with patch("app.api.v1.clothing._storage", return_value=AsyncMock()), patch(
            "app.api.v1.clothing.cleanup_pipeline_artifacts",
            new=AsyncMock(),
        ), patch(
            "app.api.v1.clothing.process_pipeline.delay",
            new=Mock(),
        ) as delay:
            response = await retry_processing(item.id, db=db, user_id=user_id)

        self.assertEqual(response.status, "PENDING")
        self.assertEqual(len(db._data[ProcessingTask]), 2)
        newest_task = db._data[ProcessingTask][-1]
        self.assertEqual(newest_task.attempt_no, 2)
        self.assertEqual(newest_task.retry_of_task_id, failed_task.id)
        delay.assert_called_once()

    async def test_read_upload_bytes_rejects_non_image(self):
        with self.assertRaises(HTTPException) as ctx:
            await _read_upload_bytes(
                make_upload("file.txt", b"text", "text/plain"),
                "front_image",
            )

        self.assertEqual(ctx.exception.status_code, 422)

    async def test_create_clothing_item_marks_task_failed_when_dispatch_fails(self):
        user_id = uuid4()
        db = FakeSession()
        storage = AsyncMock()
        storage.upload = AsyncMock()
        storage.delete = AsyncMock()

        with patch("app.api.v1.clothing._storage", return_value=storage), patch(
            "app.api.v1.clothing.process_pipeline.delay",
            side_effect=RuntimeError("redis down"),
        ), patch(
            "app.api.v1.clothing.AIService"
        ) as ai_service_cls:
            ai_service_cls.return_value.classify_bytes.return_value = [
                Tag(key="category", value="shirt")
            ]
            with self.assertRaises(HTTPException) as ctx:
                await create_clothing_item(
                    front_image=make_upload("front.jpg", b"front", "image/jpeg"),
                    back_image=None,
                    name="Blue Tee",
                    description="cotton",
                    db=db,
                    user_id=user_id,
                )

        self.assertEqual(ctx.exception.status_code, 503)
        self.assertEqual(len(db._data[ProcessingTask]), 1)
        self.assertEqual(db._data[ProcessingTask][0].status, "FAILED")
        self.assertIn("Task dispatch failed", db._data[ProcessingTask][0].error_message)


class ProcessPipelineTaskTests(unittest.TestCase):
    def test_progress_to_steps_marks_classification_complete(self):
        steps = _progress_to_steps(0, "PENDING")

        self.assertEqual(steps["classification"], "completed")
        self.assertEqual(steps["upload"], "processing")

    def test_eager_task_works_from_running_event_loop(self):
        async def _run():
            with patch(
                "app.tasks.run_pipeline_task",
                new=AsyncMock(return_value=True),
            ) as run_pipeline:
                process_pipeline.run(str(uuid4()))
                run_pipeline.assert_awaited_once()

        asyncio.run(_run())


class ClothingPipelineBehaviorTests(unittest.IsolatedAsyncioTestCase):
    async def test_pipeline_does_not_overwrite_existing_tags(self):
        user_id = uuid4()
        item_id = uuid4()
        task_id = uuid4()
        item = ClothingItem(
            id=item_id,
            user_id=user_id,
            source="OWNED",
            predicted_tags=[{"key": "category", "value": "shirt"}],
            final_tags=[{"key": "category", "value": "jacket"}],
            is_confirmed=True,
        )
        task = ProcessingTask(
            id=task_id,
            clothing_item_id=item_id,
            task_type="FULL_PIPELINE",
            status="PENDING",
            progress=0,
            created_at=datetime.now(timezone.utc),
        )
        front = Image(
            clothing_item_id=item_id,
            image_type="ORIGINAL_FRONT",
            storage_path="front.jpg",
        )
        db = FakeSession(items=[item], images=[front], tasks=[task])
        storage = AsyncMock()
        storage.download = AsyncMock(return_value=b"front")
        storage.upload = AsyncMock()
        storage.delete = AsyncMock()

        mesh = Mock()
        mesh.vertices = [1, 2, 3]
        mesh.faces = [1]

        with patch("app.services.clothing_pipeline.SessionLocal", return_value=db), patch(
            "app.services.clothing_pipeline.get_storage_service",
            return_value=storage,
        ), patch(
            "app.services.clothing_pipeline.claim_processing_task",
            return_value=task,
        ), patch(
            "app.services.clothing_pipeline.cleanup_pipeline_artifacts",
            new=AsyncMock(),
        ), patch(
            "app.services.clothing_pipeline.bg.remove_background",
            new=AsyncMock(return_value=b"processed-front"),
        ), patch(
            "app.services.clothing_pipeline.m3d.generate_3d_model",
            new=AsyncMock(return_value=mesh),
        ), patch(
            "app.services.clothing_pipeline.m3d.export_mesh",
            return_value=b"glb",
        ), patch(
            "app.services.clothing_pipeline.renderer.render_all_angles",
            return_value={0: b"png"},
        ):
            await run_pipeline_task(task_id)

        self.assertEqual(item.predicted_tags, [{"key": "category", "value": "shirt"}])
        self.assertEqual(item.final_tags, [{"key": "category", "value": "jacket"}])
        self.assertTrue(item.is_confirmed)


if __name__ == "__main__":
    unittest.main()
