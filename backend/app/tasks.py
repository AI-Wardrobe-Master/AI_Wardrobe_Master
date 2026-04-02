import asyncio
import threading
from uuid import UUID

from app.core.celery_app import celery_app
from app.services.clothing_pipeline import run_pipeline_task
from app.services.creator_pipeline import run_creator_pipeline_task


@celery_app.task(name="clothing.process_pipeline")
def process_pipeline(task_id: str, worker_id: str | None = None) -> None:
    coro = run_pipeline_task(UUID(task_id), worker_id=worker_id)
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
