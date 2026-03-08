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
        from rembg import new_session, remove as _rembg_remove

        class _RembgWrapper:
            def __init__(self):
                self.session = new_session("u2net")

            def __call__(self, img: Image.Image) -> Image.Image:
                buf = io.BytesIO()
                img.save(buf, format="PNG")
                result = _rembg_remove(buf.getvalue(), session=self.session)
                return Image.open(io.BytesIO(result)).convert("RGBA")

        _remover = _RembgWrapper()
        logger.info("Hunyuan3D rembg unavailable, using standalone rembg")

    return _remover


async def remove_background(image_bytes: bytes) -> bytes:
    """Remove background from image. Returns RGBA PNG bytes."""
    remover = _get_remover()
    image = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
    result = remover(image)

    buf = io.BytesIO()
    result.save(buf, format="PNG")
    return buf.getvalue()
