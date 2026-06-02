from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_user_id
from app.db.session import get_db
from app.schemas.agent import (
    OutfitRecommendationRequest,
    OutfitRecommendationResponse,
)
from app.services.agent_llm_service import AgentConfigurationError
from app.services.outfit_agent_service import OutfitRecommendationAgent

router = APIRouter(prefix="/agent", tags=["agent"])


@router.post(
    "/outfit-recommendation",
    response_model=OutfitRecommendationResponse,
)
def recommend_outfit(
    body: OutfitRecommendationRequest,
    db: Session = Depends(get_db),
    user_id=Depends(get_current_user_id),
):
    try:
        data = OutfitRecommendationAgent().run(db, user_id=user_id, request=body)
    except AgentConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return OutfitRecommendationResponse(data=data)
