from celery import Celery

from app.core.config import settings


celery_app = Celery(
    "ai_wardrobe_master",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=["app.tasks"],
)

celery_app.conf.update(
    task_always_eager=settings.CELERY_TASK_ALWAYS_EAGER,
    task_eager_propagates=True,
    task_default_queue="clothing_pipeline",
    worker_prefetch_multiplier=1,
    task_acks_late=True,
    task_track_started=True,
    task_routes={
        "clothing.process_pipeline": {"queue": "clothing_pipeline"},
        "styled_generation.run": {"queue": "styled_generation"},
    },
)

from celery.schedules import crontab

celery_app.conf.beat_schedule = {
    # Pre-existing: hourly sweep of blobs with ref_count=0 past 24h grace.
    "blob-gc-sweep": {
        "task": "blobs.gc_sweep",
        "schedule": crontab(minute=17),
    },
    # Orphan-file sweeper: weekly scan of local storage for unreferenced
    # files older than 24h. No-op on non-local backends.
    "blobs-gc-orphan-files": {
        "task": "blobs.gc_orphan_files",
        "schedule": 604800.0,  # weekly
    },
    # Reap-stuck beats: mark PROCESSING rows FAILED when their lease expired.
    "reap-stuck-styled-gen": {
        "task": "styled_generation.reap_stuck",
        "schedule": 3600.0,
    },
    "reap-stuck-processing-tasks": {
        "task": "processing_tasks.reap_stuck",
        "schedule": 3600.0,
    },
    # NOTE: outfit_preview_tasks has no lease_expires_at column, so no
    # reaper is registered for it (see Phase 8.2 concerns).
}
