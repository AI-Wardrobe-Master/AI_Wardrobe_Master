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


@celery_app.task(name="styled_generation.reap_stuck")
def reap_stuck_styled_generations() -> int:
    """Mark PROCESSING styled_generations with expired lease as FAILED."""
    from app.db.session import SessionLocal
    from sqlalchemy import text

    db = SessionLocal()
    try:
        result = db.execute(text("""
            UPDATE styled_generations
            SET status='FAILED',
                failure_reason='Worker timeout (lease expired)',
                updated_at=now(),
                lease_expires_at=NULL
            WHERE status='PROCESSING'
              AND lease_expires_at IS NOT NULL
              AND lease_expires_at < now()
        """))
        count = result.rowcount
        db.commit()
        if count:
            logger.info("Reaped %d stuck styled_generations", count)
        return count
    finally:
        db.close()


@celery_app.task(name="processing_tasks.reap_stuck")
def reap_stuck_processing_tasks() -> int:
    """Mark PROCESSING processing_tasks with expired lease as FAILED."""
    from app.db.session import SessionLocal
    from sqlalchemy import text

    db = SessionLocal()
    try:
        result = db.execute(text("""
            UPDATE processing_tasks
            SET status='FAILED',
                error_message='Worker timeout (lease expired)',
                lease_expires_at=NULL
            WHERE status='PROCESSING'
              AND lease_expires_at IS NOT NULL
              AND lease_expires_at < now()
        """))
        count = result.rowcount
        db.commit()
        if count:
            logger.info("Reaped %d stuck processing_tasks", count)
        return count
    finally:
        db.close()


@celery_app.task(name="blobs.gc_orphan_files")
def gc_orphan_files() -> int:
    """Sweep local blob directory for files not referenced in `blobs` table,
    older than 24 hours. Physical deletes them. Only runs on LocalBlobStorage."""
    import time
    from pathlib import Path

    from sqlalchemy import select

    from app.db.session import SessionLocal
    from app.models.blob import Blob
    from app.services.blob_storage import LocalBlobStorage, get_blob_storage

    storage = get_blob_storage()
    if not isinstance(storage, LocalBlobStorage):
        logger.info("gc_orphan_files: skipped (non-local storage)")
        return 0

    db = SessionLocal()
    try:
        known_hashes: set[str] = {
            h for (h,) in db.execute(select(Blob.blob_hash))
        }
        cutoff = time.time() - 86400  # 24h ago
        deleted = 0
        base: Path = storage.base
        if not base.exists():
            return 0
        for shard in base.iterdir():
            if not shard.is_dir():
                continue
            for sub in shard.iterdir():
                if not sub.is_dir():
                    continue
                for f in sub.iterdir():
                    if not f.is_file():
                        continue
                    name = f.name
                    # Skip non-hash files (temp uploads start with "_upload_").
                    if len(name) != 64 or name.startswith("_"):
                        continue
                    if name in known_hashes:
                        continue
                    try:
                        if f.stat().st_mtime >= cutoff:
                            continue  # too fresh — might be mid-commit
                        f.unlink()
                        deleted += 1
                    except OSError:
                        logger.exception("gc_orphan_files: failed to delete %s", f)
        if deleted:
            logger.info("gc_orphan_files: deleted %d orphan files", deleted)
        return deleted
    finally:
        db.close()
