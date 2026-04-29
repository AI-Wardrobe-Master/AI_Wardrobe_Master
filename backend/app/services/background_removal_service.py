import io
import logging

from PIL import Image

logger = logging.getLogger(__name__)

_remover = None


def _get_remover():
    """Lazy-load the background remover to avoid startup cost."""
    global _remover
    if _remover is not None:
        return _remover

    try:
        from hy3dgen.rembg import BackgroundRemover
        _remover = BackgroundRemover()
        logger.info("Using BackgroundRemover")
    except ImportError:
        class _PassthroughRemover:
            def __call__(self, img: Image.Image) -> Image.Image:
                return img

        _remover = _PassthroughRemover()
        logger.warning(
            "Hunyuan3D rembg unavailable; using passthrough background handling to avoid extra model downloads"
        )

    return _remover


async def remove_background(image_bytes: bytes) -> bytes:
    """Remove background from image. Returns RGBA PNG bytes."""
    remover = _get_remover()
    image = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
    result = remover(image)

    buf = io.BytesIO()
    result.save(buf, format="PNG")
    return buf.getvalue()
