"""
Custom exceptions
"""
from fastapi import HTTPException


class ProcessingError(HTTPException):
    """AI/Image processing failed"""

    def __init__(self, detail: str = "Processing failed"):
        super().__init__(status_code=500, detail=detail)


class ClassificationError(ProcessingError):
    """AI classification failed"""

    def __init__(self, detail: str = "Classification failed"):
        super().__init__(detail=detail)
