import asyncio
import threading
from uuid import UUID

from app.core.celery_app import celery_app
from app.services.clothing_pipeline import run_pipeline_task
from app.services.styled_generation_pipeline import run_styled_generation_task
from app.services.creator_pipeline import run_creator_pipeline_task
from app.services.outfit_preview_service import run_outfit_preview_task


def _run_async(coro) -> None:
    """Run an async coroutine from a sync Celery task context."""
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        asyncio.run(coro)
        return

    result: dict[str, BaseException | None] = {"error": None}

    def _runner() -> None:
        try:
            asyncio.run(coro)
        except BaseException as exc:  # pragma: no cover
            result["error"] = exc

    thread = threading.Thread(target=_runner, daemon=False)
    thread.start()
    thread.join()
    if result["error"] is not None:
        raise result["error"]


@celery_app.task(name="clothing.process_pipeline")
def process_pipeline(task_id: str, worker_id: str | None = None) -> None:
    _run_async(run_pipeline_task(UUID(task_id), worker_id=worker_id))


@celery_app.task(name="styled_generation.run")
def run_styled_generation(generation_id: str) -> None:
    _run_async(run_styled_generation_task(UUID(generation_id)))
@celery_app.task(name="creator.process_pipeline")
def process_creator_pipeline(task_id: str, worker_id: str | None = None) -> None:
    coro = run_creator_pipeline_task(UUID(task_id), worker_id=worker_id)
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        asyncio.run(coro)
        return

    result: dict[str, BaseException | None] = {"error": None}

    def _runner() -> None:
        try:
            asyncio.run(coro)
        except BaseException as exc:  # pragma: no cover - propagated below
            result["error"] = exc

    thread = threading.Thread(target=_runner, daemon=False)
    thread.start()
    thread.join()
    if result["error"] is not None:
        raise result["error"]


@celery_app.task(name="outfit_preview.process")
def process_outfit_preview(task_id: str, worker_id: str | None = None) -> None:
    coro = run_outfit_preview_task(UUID(task_id), worker_id=worker_id)
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        asyncio.run(coro)
        return

    result: dict[str, BaseException | None] = {"error": None}

    def _runner() -> None:
        try:
            asyncio.run(coro)
        except BaseException as exc:  # pragma: no cover - propagated below
            result["error"] = exc

    thread = threading.Thread(target=_runner, daemon=False)
    thread.start()
    thread.join()
    if result["error"] is not None:
        raise result["error"]
