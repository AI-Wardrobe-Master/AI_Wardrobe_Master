# DreamO Integration Guide

## Overview

DreamO is an **independent image generation service** that combines facial identity, garment appearance, and scene text prompts to produce realistic fashion portrait images. It is powered by the FLUX.1-dev diffusion model with DreamO's multi-condition LoRA adapters.

**DreamO does NOT replace Hunyuan3D.** The two systems serve different purposes:
- **Hunyuan3D**: Clothing digitization pipeline (2D image -> background removal -> 3D mesh -> angle rendering)
- **DreamO**: Personalized scene outfit generation (face + garment + text prompt -> realistic photo)

These are two serial but separate pipelines. DreamO consumes the garment assets produced by Hunyuan3D's background removal step.

---

## Architecture

```
                     ┌─────────────────────────────────────────────┐
                     │          Backend (FastAPI)                   │
                     │                                             │
  Flutter App ──────>│  POST /api/v1/styled-generations            │
                     │       │                                     │
                     │       v                                     │
                     │  Store selfie -> Create DB record -> Celery │
                     └──────────┬──────────────────────────────────┘
                                │ (styled_generation queue)
                                v
                     ┌──────────────────────────────────────┐
                     │   Celery Worker (celery-styled-gen)   │
                     │                                      │
                     │  1. Validate garment has PROCESSED_FRONT
                     │  2. Preprocess selfie (face + bg removal)
                     │  3. Build composite prompt             │
                     │  4. HTTP POST to DreamO service ──────────>┐
                     │  5. Store result image                 │    │
                     │  6. Update DB status                   │    │
                     └──────────────────────────────────────┘    │
                                                                  v
                                                   ┌─────────────────────┐
                                                   │  DreamO Service      │
                                                   │  (port 9000)         │
                                                   │                     │
                                                   │  GPU inference       │
                                                   │  FLUX + LoRA        │
                                                   │  Returns base64 PNG │
                                                   └─────────────────────┘
```

The DreamO service runs in its own Docker container with its own Python environment to avoid dependency conflicts with the backend.

---

## VRAM Requirements

| Mode | VRAM | Notes |
|------|------|-------|
| Full precision (bf16) | ~24 GB | Default, best quality |
| INT8 quantized | ~16 GB | Slight quality reduction |
| Nunchaku quantized | ~6.5 GB | 2-4x faster, requires nunchaku package |

Configure via `DREAMO_QUANT` environment variable: `none`, `int8`, or `nunchaku`.

GPU offloading is enabled by default (`DREAMO_OFFLOAD=true`), which moves models between CPU and GPU memory as needed, reducing peak VRAM at the cost of speed.

---

## Local Development Setup

### 1. Start DreamO Service Standalone

```bash
cd DreamO/

# Create virtual environment (separate from backend!)
python -m venv venv
source venv/bin/activate    # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Start the service
uvicorn server:app --host 0.0.0.0 --port 9000

# Verify
curl http://localhost:9000/health
```

Model weights (~12 GB) are downloaded automatically on first startup from HuggingFace (`ByteDance/DreamO`, `black-forest-labs/FLUX.1-dev`).

### 2. Start via Docker Compose

```bash
# From project root
docker compose up dreamo

# Or start everything
docker compose up
```

### 3. Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DREAMO_VERSION` | `v1.1` | DreamO model version |
| `DREAMO_OFFLOAD` | `true` | CPU offload to reduce VRAM |
| `DREAMO_NO_TURBO` | `false` | Disable turbo LoRA (slower but potentially more stable) |
| `DREAMO_QUANT` | `none` | Quantization: `none`, `int8`, `nunchaku` |
| `DREAMO_DEVICE` | `auto` | Device: `auto`, `cuda`, `mps`, `cpu` |

Backend-side variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DREAMO_SERVICE_URL` | `http://localhost:9000` | DreamO service URL |
| `DREAMO_GENERATE_TIMEOUT_SECONDS` | `300` | HTTP timeout for generation requests |

---

## DreamO Service API

### Health Check

```
GET /health
```

Response:
```json
{"status": "ok", "model_loaded": true}
```

### Generate Image

```
POST /generate
```

Request Body:
```json
{
  "id_image": "<base64 PNG>",
  "garment_image": "<base64 PNG>",
  "prompt": "a realistic full-body fashion portrait, ...",
  "negative_prompt": "blurry, low quality, ...",
  "guidance_scale": 4.5,
  "seed": -1,
  "width": 1024,
  "height": 1024,
  "num_inference_steps": 12,
  "ref_res": 512
}
```

Response:
```json
{
  "success": true,
  "output_image": "<base64 PNG>",
  "seed_used": 42
}
```

Both `id_image` and `garment_image` are optional, but at least one must be provided.

---

## Prompt Engineering

The backend assembles prompts from three templates:

1. **Base quality**: `"a realistic full-body fashion portrait, natural skin texture, detailed fabric, high quality, photographic lighting"`
2. **Garment conformity**: `"wearing the provided garment, preserve garment appearance and category, preserve clothing color and major silhouette"`
3. **User scene**: Free-text from the user (e.g., `"standing in a coffee shop, warm lighting"`)

**Negative prompt default**: `"blurry, low quality, deformed body, extra fingers, extra limbs, duplicated person, wrong clothing, bad anatomy, oversaturated face, plastic skin"`

### Guidance Scale Tips

- **3.5-4.0**: More natural, less "plastic" skin
- **4.5** (default): Balanced
- **5.0+**: Stronger text adherence, but may introduce artifacts

If results look "glossy" or "plastic", reduce guidance_scale to 3.5.

---

## Failure Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `DreamO service timed out` | GPU OOM or slow inference | Increase timeout, enable quantization, or use a larger GPU |
| `Cannot connect to DreamO service` | Service not running | Start DreamO service, check Docker compose logs |
| `Selfie validation failed: NO_FACE_DETECTED` | Face not visible in selfie | Use a clearer selfie with face clearly visible |
| `Selfie validation failed: MULTIPLE_FACES_DETECTED` | Multiple people in selfie | Use a selfie with only one person |
| `Selfie validation failed: IMAGE_TOO_DARK` | Low brightness | Use better lighting |
| `Selfie validation failed: IMAGE_TOO_BLURRY` | Camera shake or low quality | Use a sharper image |
| `Garment asset not ready` | Clothing item still processing | Wait for clothing pipeline to complete (check processing-status) |
| Result has wrong clothing | Garment image quality poor | Ensure garment has clean background removal |
| Result face doesn't match | Low quality selfie | Use a frontal, well-lit selfie |

---

## V1 Limitations

- **Single garment only**: Multi-garment composition is not supported in this version.
- **No style transfer**: The DreamO style condition is disabled for stability reasons.
- **Resolution**: Output is 768-1024px. Larger sizes are not supported.
- **Speed**: ~15-30 seconds per generation on an RTX 3080 (with turbo), longer on lower-end GPUs.
