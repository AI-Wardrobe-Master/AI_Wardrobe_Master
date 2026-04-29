"""Multi-garment pipeline test with DreamO mocked."""
import io
import uuid
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch, AsyncMock

import pytest

from app.db.session import SessionLocal
from app.models.user import User
from app.models.clothing_item import ClothingItem, Image as ClothingImage
from app.models.styled_generation import (
    StyledGeneration,
    StyledGenerationClothingItem,
)
from app.models.blob import Blob


def _suffix() -> str:
    return uuid.uuid4().hex[:8]


def _make_user(db):
    s = _suffix()
    u = User(
        id=uuid.uuid4(),
        uid=f"U-{s}",
        username=f"user-{s}",
        email=f"{s}@t.local",
        hashed_password="x",
        is_active=True,
        user_type="CREATOR",
    )
    db.add(u)
    db.flush()
    return u


def _make_blob(db, content: bytes = b"fake"):
    import hashlib
    h = hashlib.sha256(content).hexdigest()
    blob = db.query(Blob).filter_by(blob_hash=h).first()
    if blob:
        blob.ref_count += 1
    else:
        blob = Blob(
            blob_hash=h,
            byte_size=len(content),
            mime_type="image/png",
            ref_count=1,
            first_seen_at=datetime.now(timezone.utc),
            last_referenced_at=datetime.now(timezone.utc),
        )
        db.add(blob)
    db.flush()
    return blob


def _make_item_with_processed(db, user_id, name="item"):
    item = ClothingItem(
        id=uuid.uuid4(),
        user_id=user_id,
        source="OWNED",
        catalog_visibility="PRIVATE",
        predicted_tags=[],
        final_tags=[],
        is_confirmed=False,
        custom_tags=[],
        name=name,
    )
    db.add(item)
    db.flush()

    blob = _make_blob(db, content=f"fake-img-{uuid.uuid4().hex}".encode())
    img = ClothingImage(
        id=uuid.uuid4(),
        clothing_item_id=item.id,
        image_type="PROCESSED_FRONT",
        blob_hash=blob.blob_hash,
    )
    db.add(img)
    db.flush()
    return item


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.mark.asyncio
async def test_pipeline_sends_all_garments_in_slot_order(db):
    """Pipeline fetches junction rows, sorts by slot, passes to DreamO."""
    user = _make_user(db)

    # Create one item per slot, intentionally add them in a non-slot order.
    item_hat = _make_item_with_processed(db, user.id, "red cap")
    item_top = _make_item_with_processed(db, user.id, "blue jacket")
    item_pants = _make_item_with_processed(db, user.id, "jeans")
    item_shoes = _make_item_with_processed(db, user.id, "sneakers")

    # Selfie blob.
    selfie_blob = _make_blob(db, b"selfie-bytes")

    # Create the generation.
    gen = StyledGeneration(
        id=uuid.uuid4(),
        user_id=user.id,
        selfie_original_blob_hash=selfie_blob.blob_hash,
        scene_prompt="in a coffee shop",
        dreamo_version="v1.1",
        status="PENDING",
        progress=0,
        guidance_scale=4.5,
        seed=-1,
        width=1024,
        height=1024,
        gender="MALE",
    )
    db.add(gen)
    db.flush()

    # Insert junction rows — order of insertion is INTENTIONALLY scrambled;
    # pipeline must sort by slot HAT→TOP→PANTS→SHOES.
    for i, (item, slot) in enumerate([
        (item_shoes, "SHOES"),
        (item_hat, "HAT"),
        (item_pants, "PANTS"),
        (item_top, "TOP"),
    ]):
        db.add(StyledGenerationClothingItem(
            id=uuid.uuid4(),
            generation_id=gen.id,
            clothing_item_id=item.id,
            slot=slot,
            position=i,
        ))
    db.commit()

    gen_id = gen.id

    # Mock the heavy side-effects: DreamO HTTP + selfie preprocessing + blob storage.
    # We don't want this test to actually run face detection, call DreamO, or
    # write to disk. Patch at the import sites used by styled_generation_pipeline.

    async def _fake_preprocess(_bytes):
        return b"processed-selfie-bytes"

    async def _fake_get_bytes(self, blob_hash):
        return b"fake-img-" + blob_hash[:8].encode()

    async def _fake_call_dreamo(**kwargs):
        # Capture the call for inspection.
        _fake_call_dreamo.last_kwargs = kwargs
        return (b"fake-result-png", 42)

    _fake_call_dreamo.last_kwargs = None

    with (
        patch(
            "app.services.styled_generation_pipeline.preprocess_selfie",
            _fake_preprocess,
        ),
        patch(
            "app.services.styled_generation_pipeline.call_dreamo_generate",
            _fake_call_dreamo,
        ),
        patch(
            "app.services.blob_storage.LocalBlobStorage.get_bytes",
            _fake_get_bytes,
        ),
    ):
        from app.services.styled_generation_pipeline import run_styled_generation_task
        ok = await run_styled_generation_task(gen_id)

    assert ok is True
    assert _fake_call_dreamo.last_kwargs is not None
    kw = _fake_call_dreamo.last_kwargs

    # id_image present; 4 garments in slot order.
    assert kw["id_image_bytes"] == b"processed-selfie-bytes"
    assert isinstance(kw["garment_images_bytes"], list)
    assert len(kw["garment_images_bytes"]) == 4

    # Prompt contains all 4 item names, in HAT→TOP→PANTS→SHOES ordering.
    prompt = kw["prompt"]
    assert "red cap" in prompt
    assert "blue jacket" in prompt
    assert "jeans" in prompt
    assert "sneakers" in prompt
    assert prompt.index("red cap") < prompt.index("blue jacket") < prompt.index("jeans") < prompt.index("sneakers")
    assert "a man" in prompt  # gender=MALE → "a man"

    # Status is SUCCEEDED.
    db2 = SessionLocal()
    try:
        gen_after = db2.query(StyledGeneration).filter_by(id=gen_id).first()
        assert gen_after.status == "SUCCEEDED"
        assert gen_after.progress == 100
        assert gen_after.lease_expires_at is None
    finally:
        db2.close()


@pytest.mark.asyncio
async def test_pipeline_fails_if_garment_has_no_processed_front(db):
    """If any garment lacks PROCESSED_FRONT, the pipeline fails cleanly."""
    user = _make_user(db)

    item_with = _make_item_with_processed(db, user.id, "red cap")

    # Create an item WITHOUT processed image.
    item_without = ClothingItem(
        id=uuid.uuid4(),
        user_id=user.id,
        source="OWNED",
        catalog_visibility="PRIVATE",
        predicted_tags=[],
        final_tags=[],
        is_confirmed=False,
        custom_tags=[],
        name="no-processed",
    )
    db.add(item_without)
    db.flush()

    selfie_blob = _make_blob(db, b"selfie2")
    gen = StyledGeneration(
        id=uuid.uuid4(),
        user_id=user.id,
        selfie_original_blob_hash=selfie_blob.blob_hash,
        scene_prompt="outside",
        dreamo_version="v1.1",
        status="PENDING",
        progress=0,
        guidance_scale=4.5,
        seed=-1,
        width=1024,
        height=1024,
        gender="FEMALE",
    )
    db.add(gen)
    db.flush()

    db.add(StyledGenerationClothingItem(
        id=uuid.uuid4(),
        generation_id=gen.id,
        clothing_item_id=item_with.id,
        slot="HAT",
        position=0,
    ))
    db.add(StyledGenerationClothingItem(
        id=uuid.uuid4(),
        generation_id=gen.id,
        clothing_item_id=item_without.id,
        slot="TOP",
        position=1,
    ))
    db.commit()

    gen_id = gen.id

    async def _fake_preprocess(_bytes):
        return b"processed"

    async def _fake_get_bytes(self, _h):
        return b"fake"

    async def _fake_call_dreamo(**_):
        raise AssertionError("should not reach DreamO call")

    with (
        patch(
            "app.services.styled_generation_pipeline.preprocess_selfie",
            _fake_preprocess,
        ),
        patch(
            "app.services.styled_generation_pipeline.call_dreamo_generate",
            _fake_call_dreamo,
        ),
        patch(
            "app.services.blob_storage.LocalBlobStorage.get_bytes",
            _fake_get_bytes,
        ),
    ):
        from app.services.styled_generation_pipeline import run_styled_generation_task
        ok = await run_styled_generation_task(gen_id)

    assert ok is False

    db2 = SessionLocal()
    try:
        gen_after = db2.query(StyledGeneration).filter_by(id=gen_id).first()
        assert gen_after.status == "FAILED"
        assert "PROCESSED_FRONT" in (gen_after.failure_reason or "")
    finally:
        db2.close()
