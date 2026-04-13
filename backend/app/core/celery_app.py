from celery import Celery

from app.core.config import settings


celery_app = Celery(
    "ai_wardrobe_master",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
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
