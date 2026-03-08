import io
import logging

import numpy as np
import trimesh
from PIL import Image as PILImage

logger = logging.getLogger(__name__)

ANGLES = [0, 45, 90, 135, 180, 225, 270, 315]
RESOLUTION = (720, 720)


def render_all_angles(
    mesh: trimesh.Trimesh,
    resolution: tuple[int, int] = RESOLUTION,
) -> dict[int, bytes]:
    """
    Render 8 views around the Y-axis at 45-degree intervals.
    Returns {angle_degrees: png_bytes}.
    """
    scene = mesh.scene() if hasattr(mesh, "scene") and callable(mesh.scene) else trimesh.Scene(mesh)
    results: dict[int, bytes] = {}

    for angle in ANGLES:
        try:
            camera_transform = _camera_transform_for_angle(mesh, angle)
            png_bytes = scene.save_image(
                resolution=resolution,
                camera_transform=camera_transform,
            )
            if png_bytes is None:
                raise RuntimeError("scene.save_image returned None")
            results[angle] = png_bytes
        except Exception:
            logger.exception("Render failed for %d°, using placeholder", angle)
            results[angle] = _placeholder(resolution)

    return results


def _camera_transform_for_angle(mesh: trimesh.Trimesh, angle_deg: int) -> np.ndarray:
    rad = np.radians(angle_deg)
    distance = mesh.bounding_sphere.primitive.radius * 2.5
    eye = np.array([
        distance * np.sin(rad),
        0.0,
        distance * np.cos(rad),
    ]) + mesh.centroid

    forward = mesh.centroid - eye
    forward /= np.linalg.norm(forward)

    world_up = np.array([0.0, 1.0, 0.0])
    right = np.cross(forward, world_up)
    norm = np.linalg.norm(right)
    if norm < 1e-6:
        world_up = np.array([0.0, 0.0, 1.0])
        right = np.cross(forward, world_up)
        norm = np.linalg.norm(right)
    right /= norm
    up = np.cross(right, forward)

    mat = np.eye(4)
    mat[:3, 0] = right
    mat[:3, 1] = up
    mat[:3, 2] = -forward
    mat[:3, 3] = eye
    return mat


def _placeholder(resolution: tuple[int, int]) -> bytes:
    img = PILImage.new("RGBA", resolution, (200, 200, 200, 255))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()
