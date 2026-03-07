"""
AI Classification API - POST /ai/classify
Module 2.1
"""
from fastapi import APIRouter, Depends

from app.api.deps import get_current_user_id
from app.schemas.ai import ClassifyRequest, ClassifyResponse, ClassifyResponseData
from app.services.ai_service import AIService

router = APIRouter()


@router.post("/classify", response_model=ClassifyResponse)
def classify_clothing(
    body: ClassifyRequest,
    _user_id=Depends(get_current_user_id),
):
    """
    Classify clothing image, return predictedTags.
    No confidence scores in response.
    """
    ai_service = AIService()
    tags = ai_service.classify(body.image_url)
    return ClassifyResponse(
        success=True,
        data=ClassifyResponseData(predicted_tags=tags),
    )
