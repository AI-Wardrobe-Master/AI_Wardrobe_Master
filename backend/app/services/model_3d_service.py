import io
import logging
from typing import Optional

from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)

_shape_pipeline = None
_texture_pipeline = None


def _get_torch():
    """Imports torch only when a 3D generation task actually needs it.

    Returns:
        The imported `torch` module.

    Raises:
        RuntimeError: If torch is unavailable in the current backend runtime.
    """
    # Torch is intentionally lazy-loaded so normal API imports, including the
    # Agent route, do not require the heavy Hunyuan3D GPU dependency stack.
    try:
        import torch
    except ImportError as exc:
        raise RuntimeError(
            "torch is required for Hunyuan3D generation. Install the backend "
            "GPU dependencies or set HUNYUAN3D_ENABLED=false."
        ) from exc
    return torch


def _load_pipelines():
    """Loads Hunyuan3D shape and optional texture pipelines once.

    Returns:
        None. The loaded pipelines are cached in module-level variables.
    """
    global _shape_pipeline, _texture_pipeline

    # Pipeline loading is expensive, so reuse the already-loaded shape pipeline
    # across generation requests.
    if _shape_pipeline is not None:
        return

    # Import Hunyuan3D only inside the loader so API processes that never run 3D
    # generation do not need this optional dependency at import time.
    from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

    logger.info("Loading Hunyuan3D-2 shape pipeline...")
    _shape_pipeline = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        settings.HUNYUAN3D_MODEL_PATH,
        subfolder=settings.HUNYUAN3D_SHAPE_SUBFOLDER,
    )
    if settings.HUNYUAN3D_LOW_VRAM:
        logger.info("Enabling Hunyuan3D shape CPU offload for low VRAM")
        _shape_pipeline.enable_model_cpu_offload()

    # Texture generation is optional because local development and low-VRAM
    # deployments often need shape-only generation.
    if settings.HUNYUAN3D_SKIP_TEXTURE:
        logger.info("Skipping Hunyuan3D-Paint texture pipeline")
        _texture_pipeline = None
        return

    # Texture pipeline is loaded only when enabled; it uses the same model path
    # but a different Hunyuan3D pipeline implementation.
    from hy3dgen.texgen import Hunyuan3DPaintPipeline

    logger.info("Loading Hunyuan3D-Paint texture pipeline...")
    _texture_pipeline = Hunyuan3DPaintPipeline.from_pretrained(
        settings.HUNYUAN3D_MODEL_PATH
    )
    if settings.HUNYUAN3D_LOW_VRAM:
        logger.info("Enabling Hunyuan3D texture CPU offload for low VRAM")
        _texture_pipeline.enable_model_cpu_offload()
    logger.info("Hunyuan3D-2 pipelines loaded")


async def generate_3d_model(
    front_image_bytes: bytes,
    back_image_bytes: Optional[bytes] = None,
) -> "trimesh.Trimesh":
    """Generates a 3D garment mesh from preprocessed clothing images.

    Args:
        front_image_bytes: Front garment image bytes, expected to be background
            removed RGBA PNG data.
        back_image_bytes: Optional back garment image bytes. Reserved for
            future multi-view generation support.

    Returns:
        Generated trimesh mesh.

    Raises:
        RuntimeError: If torch is unavailable when 3D generation is enabled.
    """
    _load_pipelines()

    # The current Hunyuan3D integration uses the front image as the visual
    # condition. Back-image support is kept in the signature for API stability.
    front = Image.open(io.BytesIO(front_image_bytes)).convert("RGBA")
    torch = _get_torch()

    # Inference mode avoids gradient bookkeeping and reduces memory usage during
    # generation.
    with torch.inference_mode():
        mesh = _shape_pipeline(
            image=front,
            num_inference_steps=settings.HUNYUAN3D_SHAPE_STEPS,
            octree_resolution=settings.HUNYUAN3D_OCTREE_RESOLUTION,
            num_chunks=settings.HUNYUAN3D_NUM_CHUNKS,
        )[0]

        # Texture generation is applied only when the optional texture pipeline
        # was loaded by _load_pipelines().
        if _texture_pipeline is not None:
            mesh = _texture_pipeline(mesh, image=front)

    logger.info(
        "3D model generated: %d verts, %d faces",
        len(mesh.vertices), len(mesh.faces),
    )
    return mesh


def export_mesh(mesh, fmt: str = "glb") -> bytes:
    """Exports a trimesh mesh to binary bytes.

    Args:
        mesh: Trimesh-compatible mesh object.
        fmt: Output mesh format, defaulting to `glb`.

    Returns:
        Serialized mesh bytes.
    """
    # trimesh exports into file-like objects, so use an in-memory buffer instead
    # of writing temporary files.
    buf = io.BytesIO()
    mesh.export(buf, file_type=fmt)
    return buf.getvalue()
