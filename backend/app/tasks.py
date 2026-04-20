import asyncio
import logging
import threading
from datetime import datetime, timedelta, timezone
from uuid import UUID

from app.core.celery_app import celery_app
from app.services.blob_storage import get_blob_storage
from app.services.clothing_pipeline import run_pipeline_task
from app.services.styled_generation_pipeline import run_styled_generation_task
from app.services.outfit_preview_service import run_outfit_preview_task

logger = logging.getLogger(__name__)


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


@celery_app.task(name="blobs.gc_sweep")
def gc_sweep() -> None:
    """Sweep blobs with ref_count=0 and pending_delete_at older than 24h."""
    from app.db.session import SessionLocal
    from app.models.blob import Blob
    from sqlalchemy import text

    db = SessionLocal()
    blob_storage = get_blob_storage()
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
        candidates = (
            db.query(Blob)
            .filter(
                Blob.pending_delete_at.isnot(None),
                Blob.pending_delete_at < cutoff,
                Blob.ref_count == 0,
            )
            .limit(1000)
            .all()
        )

        deleted_count = 0
        for candidate in candidates:
            try:
                db.execute(
                    text("SELECT pg_advisory_xact_lock(hashtext(:h))"),
                    {"h": candidate.blob_hash},
                )
                row = (
                    db.query(Blob)
                    .filter(
                        Blob.blob_hash == candidate.blob_hash,
                        Blob.ref_count == 0,
                        Blob.pending_delete_at < cutoff,
                    )
                    .first()
                )
                if row is None:
                    db.commit()
                    continue

                db.delete(row)
                db.flush()

                try:
                    asyncio.run(blob_storage.physical_delete(candidate.blob_hash))
                except FileNotFoundError:
                    pass

                db.commit()
                deleted_count += 1
            except Exception:
                db.rollback()
                logger.exception("GC failed for %s", candidate.blob_hash)

        if deleted_count:
            logger.info("GC swept %d orphaned blobs", deleted_count)
    finally:
        db.close()
