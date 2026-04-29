import io
import logging

import cv2
import numpy as np
from PIL import Image

from app.core.config import settings
from app.services.background_removal_service import remove_background

logger = logging.getLogger(__name__)


class SelfiePreprocessingError(Exception):
    """Raised when selfie image validation or preprocessing fails."""

    pass


async def preprocess_selfie(image_bytes: bytes) -> bytes:
    """
    Validate and preprocess a selfie image for DreamO ID conditioning.

    Steps:
        1. Decode and validate image format
        2. Detect exactly one face (OpenCV Haar cascade)
        3. Check brightness and sharpness
        4. Remove background
        5. Composite onto white background
        6. Resize to target resolution

    Returns:
        PNG bytes with white background, ready for DreamO.

    Raises:
        SelfiePreprocessingError with codes:
            NO_FACE_DETECTED, MULTIPLE_FACES_DETECTED,
            IMAGE_TOO_DARK, IMAGE_TOO_BLURRY
    """
    # Decode
    try:
        img = Image.open(io.BytesIO(image_bytes))
    except Exception:
        raise SelfiePreprocessingError("INVALID_IMAGE_FORMAT")

    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGB")

    # Face detection via OpenCV Haar cascade
    img_rgb = np.array(img.convert("RGB"))
    img_bgr = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)

    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    faces = face_cascade.detectMultiScale(
        gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60)
    )

    if len(faces) == 0:
        raise SelfiePreprocessingError("NO_FACE_DETECTED")
    if len(faces) > 1:
        raise SelfiePreprocessingError("MULTIPLE_FACES_DETECTED")

    # Brightness check
    mean_brightness = float(np.mean(gray))
    if mean_brightness < 40:
        raise SelfiePreprocessingError("IMAGE_TOO_DARK")

    # Blur check (Laplacian variance)
    laplacian_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    if laplacian_var < 50:
        raise SelfiePreprocessingError("IMAGE_TOO_BLURRY")

    # Background removal (reuse existing backend service)
    processed_bytes = await remove_background(image_bytes)

    # Composite RGBA onto white background
    processed = Image.open(io.BytesIO(processed_bytes)).convert("RGBA")
    white_bg = Image.new("RGB", processed.size, (255, 255, 255))
    white_bg.paste(processed, mask=processed.split()[3])

    # Resize keeping aspect ratio
    target = settings.SELFIE_TARGET_RESOLUTION
    white_bg.thumbnail((target, target), Image.Resampling.LANCZOS)

    buf = io.BytesIO()
    white_bg.save(buf, format="PNG")
    return buf.getvalue()
