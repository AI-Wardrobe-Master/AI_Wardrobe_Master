"""Concurrency test: release() + addref() on same hash must not lose updates."""

import asyncio
import io
import pytest
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.services.blob_service import BlobService


@pytest.mark.asyncio
async def test_release_and_addref_concurrent_preserve_ref_count():
    """After N parallel (addref, release) pairs on same hash starting from 1,
    ref_count must end at 1 — proving neither write is lost."""
    db: Session = SessionLocal()
    svc = BlobService()
    # Ingest one blob so the row exists with ref_count=1.
    initial = await svc.ingest_upload(
        db, io.BytesIO(b"race-test-payload"),
        claimed_mime_type="application/octet-stream",
        max_size=1024,
    )
    db.commit()
    h = initial.blob_hash

    # Run 50 addref/release pairs concurrently.
    def work():
        local_db = SessionLocal()
        try:
            svc.addref(local_db, h)
            local_db.commit()
            svc.release(local_db, h)
            local_db.commit()
        finally:
            local_db.close()

    loop = asyncio.get_event_loop()
    await asyncio.gather(*[loop.run_in_executor(None, work) for _ in range(50)])

    db.refresh(initial)
    assert initial.ref_count == 1, f"lost update: ref_count={initial.ref_count}"

    # Cleanup
    svc.release(db, h)
    db.commit()
    db.close()
