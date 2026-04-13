from typing import List, Optional, Tuple
from uuid import UUID

from sqlalchemy.orm import Session

from app.models.styled_generation import StyledGeneration


def create(db: Session, generation: StyledGeneration) -> StyledGeneration:
    db.add(generation)
    db.flush()
    return generation


def get(
    db: Session, gen_id: UUID, user_id: UUID
) -> Optional[StyledGeneration]:
    return (
        db.query(StyledGeneration)
        .filter(
            StyledGeneration.id == gen_id,
            StyledGeneration.user_id == user_id,
        )
        .first()
    )


def list_by_user(
    db: Session,
    user_id: UUID,
    *,
    page: int = 1,
    limit: int = 20,
) -> Tuple[List[StyledGeneration], int]:
    q = (
        db.query(StyledGeneration)
        .filter(StyledGeneration.user_id == user_id)
        .order_by(StyledGeneration.created_at.desc())
    )
    total = q.count()
    items = q.offset((page - 1) * limit).limit(limit).all()
    return items, total


def update_status(
    db: Session,
    gen_id: UUID,
    *,
    status: str,
    progress: int = 0,
    result_image_path: Optional[str] = None,
    selfie_processed_path: Optional[str] = None,
    failure_reason: Optional[str] = None,
    seed: Optional[int] = None,
) -> Optional[StyledGeneration]:
    gen = (
        db.query(StyledGeneration)
        .filter(StyledGeneration.id == gen_id)
        .first()
    )
    if gen is None:
        return None
    gen.status = status
    gen.progress = progress
    if result_image_path is not None:
        gen.result_image_path = result_image_path
    if selfie_processed_path is not None:
        gen.selfie_processed_path = selfie_processed_path
    if failure_reason is not None:
        gen.failure_reason = failure_reason
    if seed is not None:
        gen.seed = seed
    db.flush()
    return gen


def delete(db: Session, gen_id: UUID, user_id: UUID) -> bool:
    gen = get(db, gen_id, user_id)
    if gen is None:
        return False
    db.delete(gen)
    db.flush()
    return True
