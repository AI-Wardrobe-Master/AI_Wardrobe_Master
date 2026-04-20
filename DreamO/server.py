"""
DreamO Generation Service

Standalone FastAPI HTTP wrapper around the DreamO Generator class.
Accepts base64-encoded images (face ID + garment) and a text prompt,
returns a base64-encoded result image.

This service runs in its own Python environment with its own
torch/diffusers/transformers versions to avoid conflicts with the
main backend.
"""

import base64
import io
import logging
import os
import threading
from typing import Optional

import numpy as np
import torch
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel, Field

from dreamo_generator import Generator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="DreamO Generation Service", version="1.0.0")

_generator: Optional[Generator] = None
_lock = threading.Lock()


class GenerateRequest(BaseModel):
    id_image: Optional[str] = None
    garment_images: Optional[list[str]] = Field(default=None)  # NEW
    garment_image: Optional[str] = None                        # DEPRECATED shim
    prompt: str
    negative_prompt: str = ""
    guidance_scale: float = Field(default=4.5, ge=1.0, le=10.0)
    seed: int = -1
    width: int = Field(default=1024, ge=768, le=1024)
    height: int = Field(default=1024, ge=768, le=1024)
    num_inference_steps: int = Field(default=12, ge=4, le=50)
    ref_res: int = Field(default=512, ge=256, le=1024)


class GenerateResponse(BaseModel):
    success: bool
    output_image: Optional[str] = None
    seed_used: Optional[int] = None
    error: Optional[str] = None


def _decode_image(b64_str: str) -> np.ndarray:
    """Decode a base64 string to a numpy RGB array."""
    raw = base64.b64decode(b64_str)
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    return np.array(img)


def _encode_image(pil_img: Image.Image) -> str:
    """Encode a PIL image to base64 PNG string."""
    buf = io.BytesIO()
    pil_img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")


@app.on_event("startup")
def load_model():
    global _generator
    logger.info("Loading DreamO model...")
    _generator = Generator(
        version=os.getenv("DREAMO_VERSION", "v1.1"),
        offload=os.getenv("DREAMO_OFFLOAD", "true").lower() == "true",
        no_turbo=os.getenv("DREAMO_NO_TURBO", "false").lower() == "true",
        quant=os.getenv("DREAMO_QUANT", "none"),
        device=os.getenv("DREAMO_DEVICE", "auto"),
    )
    logger.info("DreamO model loaded successfully.")


@app.get("/health")
def health():
    return {"status": "ok", "model_loaded": _generator is not None}


@app.post("/generate", response_model=GenerateResponse)
def generate(req: GenerateRequest):
    if _generator is None:
        raise HTTPException(503, "Model not loaded yet")

    garments_list: list[str] = req.garment_images or (
        [req.garment_image] if req.garment_image else []
    )

    if req.id_image is None and not garments_list:
        raise HTTPException(
            422, "At least one of id_image or garment_images must be provided"
        )

    try:
        ref_images = []
        ref_tasks = []

        if req.id_image:
            ref_images.append(_decode_image(req.id_image))
            ref_tasks.append("id")

        for g in garments_list:
            ref_images.append(_decode_image(g))
            ref_tasks.append("ip")

        with _lock:
            ref_conds, _, seed = _generator.pre_condition(
                ref_images=ref_images,
                ref_tasks=ref_tasks,
                ref_res=req.ref_res,
                seed=str(req.seed),
            )

            result = _generator.dreamo_pipeline(
                prompt=req.prompt,
                negative_prompt=req.negative_prompt or None,
                width=req.width,
                height=req.height,
                num_inference_steps=req.num_inference_steps,
                guidance_scale=req.guidance_scale,
                ref_conds=ref_conds,
                generator=torch.Generator(device="cpu").manual_seed(seed),
                true_cfg_scale=1.0,
                true_cfg_start_step=0,
                true_cfg_end_step=0,
                neg_guidance_scale=3.5,
                first_step_guidance_scale=req.guidance_scale,
            )

        output_image = result.images[0]
        output_b64 = _encode_image(output_image)

        return GenerateResponse(
            success=True,
            output_image=output_b64,
            seed_used=seed,
        )

    except Exception as exc:
        logger.exception("Generation failed")
        return GenerateResponse(
            success=False,
            error=str(exc)[:500],
        )
