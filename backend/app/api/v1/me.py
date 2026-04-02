from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.crud import creator as crud_creator
from app.db.session import get_db
from app.models.user import User
from app.schemas.creator import (
    CreatorCapabilities,
    CreatorProfileSummary,
    MeData,
    MeResponse,
)

router = APIRouter(tags=["me"])


@router.get("/me", response_model=MeResponse)
def get_me(
    db: Session = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    user = db.get(User, user_id)
    profile = crud_creator.get_by_user_id(db, user_id)
    creator_status = profile.status if profile else None
    return MeResponse(
        data=MeData(
            id=user.id,
            username=user.username,
            email=user.email,
            type=user.user_type,
            creatorProfile=CreatorProfileSummary(
                exists=profile is not None,
                status=creator_status,
                displayName=profile.display_name if profile else None,
                brandName=profile.brand_name if profile else None,
            ),
            capabilities=CreatorCapabilities(
                canApplyForCreator=profile is None,
                canPublishItems=creator_status == "ACTIVE",
                canCreateCardPacks=creator_status == "ACTIVE",
                canEditCreatorProfile=creator_status == "ACTIVE",
                canViewCreatorCenter=profile is not None,
            ),
        )
    )
