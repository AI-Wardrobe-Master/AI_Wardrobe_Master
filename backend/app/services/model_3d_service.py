import io
import logging
from typing import Optional

from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)

_shape_pipeline = None
_texture_pipeline = None


def _load_pipelines():
    global _shape_pipeline, _texture_pipeline
    if _shape_pipeline is not None:
        return

    from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

    logger.info("Loading Hunyuan3D-2 shape pipeline...")
    _shape_pipeline = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        settings.HUNYUAN3D_MODEL_PATH,
        subfolder=settings.HUNYUAN3D_SHAPE_SUBFOLDER,
    )
    if settings.HUNYUAN3D_LOW_VRAM:
        logger.info("Enabling Hunyuan3D shape CPU offload for low VRAM")
        _shape_pipeline.enable_model_cpu_offload()

    if settings.HUNYUAN3D_SKIP_TEXTURE:
        logger.info("Skipping Hunyuan3D-Paint texture pipeline")
        _texture_pipeline = None
        return

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
    """
    Generate a textured 3D mesh from front (required) and back (optional) images.
    Images should already have background removed (RGBA PNG).
    """
    _load_pipelines()

    front = Image.open(io.BytesIO(front_image_bytes)).convert("RGBA")
    import torch

    with torch.inference_mode():
        mesh = _shape_pipeline(
            image=front,
            num_inference_steps=settings.HUNYUAN3D_SHAPE_STEPS,
            octree_resolution=settings.HUNYUAN3D_OCTREE_RESOLUTION,
            num_chunks=settings.HUNYUAN3D_NUM_CHUNKS,
        )[0]
        if _texture_pipeline is not None:
            mesh = _texture_pipeline(mesh, image=front)

    logger.info(
        "3D model generated: %d verts, %d faces",
        len(mesh.vertices), len(mesh.faces),
    )
    return mesh


def export_mesh(mesh, fmt: str = "glb") -> bytes:
    """Export trimesh to bytes in the given format."""
    buf = io.BytesIO()
    mesh.export(buf, file_type=fmt)
    return buf.getvalue()
