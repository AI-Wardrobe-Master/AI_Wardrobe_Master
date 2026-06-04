import io
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy.orm import Session
from PIL import Image as PILImage

from app.api.deps import get_current_user_id
from app.core.config import settings
from app.db.session import get_db
from app.models.user_tryon_image import UserTryOnImage
from app.schemas.tryon_image import TryOnImageData, TryOnImageResponse
from app.services.blob_service import get_blob_service

router = APIRouter(prefix="/me/tryon-image", tags=["try-on-image"])


@router.get("", response_model=TryOnImageResponse)
def get_default_tryon_image(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    image = _get_default_tryon_image(db, user_id=user_id)
    return TryOnImageResponse(data=_to_tryon_image_data(image) if image else None)


@router.post("", response_model=TryOnImageResponse, status_code=201)
async def upload_default_tryon_image(
    person_image: UploadFile = File(...),
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    payload = await person_image.read()
    if not payload:
        raise HTTPException(status_code=422, detail="person_image is empty")
    if len(payload) > settings.MAX_UPLOAD_SIZE_BYTES:
        raise HTTPException(
            status_code=413,
            detail="person_image exceeds size limit",
        )
    try:
        with PILImage.open(io.BytesIO(payload)) as image:
            image.verify()
            image_format = (image.format or "JPEG").lower()
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail="person_image must be a valid image",
        ) from exc
    claimed_mime_type = (
        person_image.content_type
        if person_image.content_type and person_image.content_type.startswith("image/")
        else f"image/{'jpeg' if image_format == 'jpg' else image_format}"
    )

    blob_service = get_blob_service()
    existing = _get_default_tryon_image(db, user_id=user_id)
    old_blob_hash = existing.blob_hash if existing else None

    try:
        blob = await blob_service.ingest_upload(
            db,
            io.BytesIO(payload),
            claimed_mime_type=claimed_mime_type,
            max_size=settings.MAX_UPLOAD_SIZE_BYTES,
        )
        now = datetime.now(timezone.utc)
        if existing is None:
            existing = UserTryOnImage(
                user_id=user_id,
                blob_hash=blob.blob_hash,
                person_view_type="FULL_BODY",
                is_default=True,
                created_at=now,
                updated_at=now,
            )
            db.add(existing)
        else:
            existing.blob_hash = blob.blob_hash
            existing.person_view_type = "FULL_BODY"
            existing.is_default = True
            existing.updated_at = now
        if old_blob_hash is not None:
            blob_service.release(db, old_blob_hash)
        db.commit()
        db.refresh(existing)
    except Exception:
        db.rollback()
        raise

    return TryOnImageResponse(data=_to_tryon_image_data(existing))


@router.delete("", response_model=TryOnImageResponse)
def delete_default_tryon_image(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    image = _get_default_tryon_image(db, user_id=user_id)
    if image is None:
        return TryOnImageResponse(data=None)

    blob_hash = image.blob_hash
    db.delete(image)
    get_blob_service().release(db, blob_hash)
    db.commit()
    return TryOnImageResponse(data=None)


def _get_default_tryon_image(
    db: Session,
    *,
    user_id: UUID,
) -> UserTryOnImage | None:
    return (
        db.query(UserTryOnImage)
        .filter(
            UserTryOnImage.user_id == user_id,
            UserTryOnImage.is_default.is_(True),
        )
        .first()
    )


def _to_tryon_image_data(image: UserTryOnImage) -> TryOnImageData:
    return TryOnImageData(
        id=image.id,
        personViewType=image.person_view_type,
        imageUrl=f"/files/me/tryon-image/{image.id}",
        isDefault=image.is_default,
        createdAt=image.created_at,
        updatedAt=image.updated_at,
    )
