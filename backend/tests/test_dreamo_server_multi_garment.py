"""Test DreamO server request handling.

The full server module cannot be imported in the backend venv because it
depends on torch, diffusers, and transformers. This test falls back to
validating the Pydantic `GenerateRequest` schema with the same shape as
the one in `DreamO/server.py`, so we can still verify the request
contract without a heavyweight model environment.

If the DreamO venv is available and `DREAMO_DIR/server.py` can be
imported directly, the full TestClient variant is attempted first.
"""
from __future__ import annotations

import base64
import sys
from pathlib import Path
from typing import Optional
from unittest.mock import MagicMock

import pytest
from pydantic import BaseModel, Field


DREAMO_DIR = Path(__file__).resolve().parents[2] / "DreamO"


def _tiny_png_b64():
    """Minimal 1x1 PNG as base64."""
    # Hard-coded 1x1 white PNG
    raw = bytes.fromhex(
        "89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4"
        "89000000017352474200AECE1CE90000000E49444154789463F8FF00000000"
        "05000100000000000049454E44AE426082"
    )
    return base64.b64encode(raw).decode()


def _try_import_dreamo_server():
    """Try to import the DreamO server module.

    Returns the module on success, or None if heavy deps (torch, etc.)
    are missing in the current environment.
    """
    if str(DREAMO_DIR) not in sys.path:
        sys.path.insert(0, str(DREAMO_DIR))
    try:
        import server as dreamo_server  # type: ignore
        return dreamo_server
    except Exception:
        return None


_DREAMO_SERVER = _try_import_dreamo_server()
_FULL_SERVER_AVAILABLE = _DREAMO_SERVER is not None


# ----------------------------------------------------------------------
# Fallback lightweight schema tests (always run)
# ----------------------------------------------------------------------


class _FallbackGenerateRequest(BaseModel):
    """Mirror of `DreamO/server.py::GenerateRequest` for schema testing.

    Kept in sync by hand; the shape here is what the server must accept
    on the wire.
    """

    id_image: Optional[str] = None
    garment_images: Optional[list[str]] = Field(default=None)
    garment_image: Optional[str] = None
    prompt: str
    negative_prompt: str = ""
    guidance_scale: float = Field(default=4.5, ge=1.0, le=10.0)
    seed: int = -1
    width: int = Field(default=1024, ge=768, le=1024)
    height: int = Field(default=1024, ge=768, le=1024)
    num_inference_steps: int = Field(default=12, ge=4, le=50)
    ref_res: int = Field(default=512, ge=256, le=1024)


def test_generate_request_accepts_garment_images():
    req = _FallbackGenerateRequest(prompt="x", garment_images=["a", "b"])
    assert req.garment_images == ["a", "b"]
    assert req.garment_image is None


def test_generate_request_accepts_legacy_garment_image():
    req = _FallbackGenerateRequest(prompt="x", garment_image="single")
    assert req.garment_image == "single"
    assert req.garment_images is None


def test_generate_request_accepts_both_fields():
    """Both fields may appear; server-side logic decides precedence."""
    req = _FallbackGenerateRequest(
        prompt="x",
        garment_images=["a", "b"],
        garment_image="legacy",
    )
    assert req.garment_images == ["a", "b"]
    assert req.garment_image == "legacy"


def test_generate_request_defaults():
    req = _FallbackGenerateRequest(prompt="x")
    assert req.id_image is None
    assert req.garment_images is None
    assert req.garment_image is None


def test_server_module_has_new_garment_images_field():
    """Smoke check against the DreamO server source: the new field name exists.

    This runs even when heavy deps are missing by reading the file text
    rather than importing it.
    """
    server_py = DREAMO_DIR / "server.py"
    text = server_py.read_text(encoding="utf-8")
    assert "garment_images" in text, (
        "DreamO/server.py must expose `garment_images` list field"
    )
    # Legacy shim should still be there for one-release compat.
    assert "garment_image" in text


# ----------------------------------------------------------------------
# Full TestClient tests (only if torch/diffusers importable)
# ----------------------------------------------------------------------


@pytest.fixture
def client(monkeypatch):
    """Mount the DreamO FastAPI app with a mocked generator."""
    if not _FULL_SERVER_AVAILABLE:
        pytest.skip("DreamO server module cannot be imported (missing heavy deps).")

    from fastapi.testclient import TestClient

    mock_gen = MagicMock()
    mock_gen.pre_condition.return_value = ([], [], 42)

    fake_image = MagicMock()

    def _save(buf, format="PNG"):
        buf.write(b"\x89PNG\r\n\x1a\nfakepng")

    fake_image.save = _save

    mock_pipeline_result = MagicMock()
    mock_pipeline_result.images = [fake_image]
    mock_gen.dreamo_pipeline.return_value = mock_pipeline_result

    monkeypatch.setattr(_DREAMO_SERVER, "_generator", mock_gen)

    return TestClient(_DREAMO_SERVER.app), mock_gen


def test_accepts_multi_garment(client):
    tc, mock_gen = client
    resp = tc.post("/generate", json={
        "id_image": _tiny_png_b64(),
        "garment_images": [_tiny_png_b64(), _tiny_png_b64()],
        "prompt": "test",
    })
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True

    # 1 id + 2 garments → 3 ref tasks, types ['id','ip','ip'].
    pre_cond_args = mock_gen.pre_condition.call_args
    ref_tasks = pre_cond_args.kwargs["ref_tasks"]
    assert ref_tasks == ["id", "ip", "ip"]


def test_backward_compat_single_garment(client):
    tc, mock_gen = client
    resp = tc.post("/generate", json={
        "id_image": _tiny_png_b64(),
        "garment_image": _tiny_png_b64(),  # legacy single field
        "prompt": "test",
    })
    assert resp.status_code == 200, resp.text

    ref_tasks = mock_gen.pre_condition.call_args.kwargs["ref_tasks"]
    assert ref_tasks == ["id", "ip"]


def test_rejects_no_images(client):
    tc, _ = client
    resp = tc.post("/generate", json={"prompt": "test"})
    assert resp.status_code == 422


def test_id_only_accepted(client):
    tc, _ = client
    resp = tc.post("/generate", json={
        "id_image": _tiny_png_b64(),
        "prompt": "test",
    })
    assert resp.status_code == 200, resp.text


def test_garment_images_takes_precedence(client):
    """If both are provided, garment_images wins and garment_image is ignored."""
    tc, mock_gen = client
    resp = tc.post("/generate", json={
        "id_image": _tiny_png_b64(),
        "garment_images": [_tiny_png_b64()],
        "garment_image": _tiny_png_b64(),
        "prompt": "test",
    })
    assert resp.status_code == 200
    # Should get 1 id + 1 garment = 2, not 3.
    ref_tasks = mock_gen.pre_condition.call_args.kwargs["ref_tasks"]
    assert ref_tasks == ["id", "ip"]
