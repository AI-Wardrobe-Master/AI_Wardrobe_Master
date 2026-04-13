import base64
import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class DreamOServiceError(Exception):
    """Raised when the DreamO inference service returns an error."""

    pass


async def call_dreamo_generate(
    *,
    id_image_bytes: bytes | None = None,
    garment_image_bytes: bytes | None = None,
    prompt: str,
    negative_prompt: str = "",
    guidance_scale: float = 4.5,
    seed: int = -1,
    width: int = 1024,
    height: int = 1024,
    num_inference_steps: int = 12,
) -> tuple[bytes, int]:
    """
    Call the isolated DreamO service POST /generate endpoint.

    Args:
        id_image_bytes: Preprocessed selfie image (white bg) for face ID.
        garment_image_bytes: Processed garment image (no bg) for try-on.
        prompt: Assembled generation prompt.
        negative_prompt: Negative prompt for quality control.
        guidance_scale: Classifier-free guidance strength.
        seed: Random seed (-1 for random).
        width: Output image width (768-1024).
        height: Output image height (768-1024).
        num_inference_steps: Denoising steps.

    Returns:
        Tuple of (result_image_bytes, seed_used).

    Raises:
        DreamOServiceError on HTTP or inference failure.
    """
    payload: dict = {
        "prompt": prompt,
        "negative_prompt": negative_prompt,
        "guidance_scale": guidance_scale,
        "seed": seed,
        "width": width,
        "height": height,
        "num_inference_steps": num_inference_steps,
    }

    if id_image_bytes:
        payload["id_image"] = base64.b64encode(id_image_bytes).decode()
    if garment_image_bytes:
        payload["garment_image"] = base64.b64encode(
            garment_image_bytes
        ).decode()

    url = f"{settings.DREAMO_SERVICE_URL}/generate"
    timeout = settings.DREAMO_GENERATE_TIMEOUT_SECONDS

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(url, json=payload)
    except httpx.TimeoutException:
        raise DreamOServiceError(
            "DreamO service timed out. The model may be overloaded."
        )
    except httpx.ConnectError:
        raise DreamOServiceError(
            "Cannot connect to DreamO service. Is it running?"
        )

    if resp.status_code != 200:
        raise DreamOServiceError(
            f"DreamO returned HTTP {resp.status_code}: {resp.text[:200]}"
        )

    data = resp.json()
    if not data.get("success"):
        raise DreamOServiceError(
            data.get("error", "Unknown DreamO error")
        )

    result_bytes = base64.b64decode(data["output_image"])
    seed_used = data.get("seed_used", seed)
    return result_bytes, seed_used
