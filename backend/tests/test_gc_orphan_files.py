"""Test orphan file GC sweeper."""
import hashlib
import time
from pathlib import Path

import pytest


def _write_fake_blob_file(base: Path, content: bytes, mtime_seconds_ago: int = 0) -> str:
    """Write bytes as if it were a blob under base/hash[:2]/hash[2:4]/hash. Returns hash."""
    h = hashlib.sha256(content).hexdigest()
    target = base / h[:2] / h[2:4] / h
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
    if mtime_seconds_ago > 0:
        mtime = time.time() - mtime_seconds_ago
        import os
        os.utime(target, (mtime, mtime))
    return h


def test_gc_orphan_files_deletes_old_unreferenced(tmp_path, monkeypatch):
    """Files not in blobs table AND older than 24h should be deleted.
    Fresh orphans are left alone (might be in-flight)."""
    from app.services.blob_storage import LocalBlobStorage

    # Monkey-patch LocalBlobStorage to use tmp_path.
    monkeypatch.setattr(
        "app.core.config.settings.LOCAL_STORAGE_PATH", str(tmp_path / "storage"),
    )
    # Recompute the storage base.
    storage = LocalBlobStorage()
    base = storage.base

    # Write two orphan files: one old (should be deleted), one fresh (should be kept).
    old_hash = _write_fake_blob_file(
        base, b"old-orphan-bytes",
        mtime_seconds_ago=3 * 86400,   # 3 days old
    )
    fresh_hash = _write_fake_blob_file(
        base, b"fresh-orphan-bytes",
        mtime_seconds_ago=0,           # just created
    )

    # Sanity: files exist on disk.
    assert (base / old_hash[:2] / old_hash[2:4] / old_hash).exists()
    assert (base / fresh_hash[:2] / fresh_hash[2:4] / fresh_hash).exists()

    # Run the GC.
    from app.tasks import gc_orphan_files
    # NB: gc_orphan_files reads settings to pick storage. The monkeypatch
    # above is enough because get_blob_storage() is called inside the task.
    deleted = gc_orphan_files()

    assert deleted >= 1
    # Old orphan gone.
    assert not (base / old_hash[:2] / old_hash[2:4] / old_hash).exists()
    # Fresh orphan preserved (age-guard).
    assert (base / fresh_hash[:2] / fresh_hash[2:4] / fresh_hash).exists()


def test_gc_orphan_files_preserves_referenced(tmp_path, monkeypatch):
    """A file that IS referenced in the blobs table must NOT be deleted."""
    from app.services.blob_storage import LocalBlobStorage
    from app.db.session import SessionLocal
    from app.models.blob import Blob
    from datetime import datetime, timezone

    monkeypatch.setattr(
        "app.core.config.settings.LOCAL_STORAGE_PATH", str(tmp_path / "storage"),
    )
    storage = LocalBlobStorage()
    base = storage.base

    known_hash = _write_fake_blob_file(
        base, b"referenced-bytes",
        mtime_seconds_ago=3 * 86400,
    )

    # Insert the Blob row so the GC sees it as referenced.
    db = SessionLocal()
    try:
        row = Blob(
            blob_hash=known_hash,
            byte_size=len(b"referenced-bytes"),
            mime_type="application/octet-stream",
            ref_count=1,
            first_seen_at=datetime.now(timezone.utc),
            last_referenced_at=datetime.now(timezone.utc),
        )
        db.add(row)
        db.commit()
    finally:
        db.close()

    try:
        from app.tasks import gc_orphan_files
        gc_orphan_files()

        # File must still exist.
        assert (base / known_hash[:2] / known_hash[2:4] / known_hash).exists()
    finally:
        # Cleanup: remove the test blob row.
        db = SessionLocal()
        try:
            blob = db.query(Blob).filter_by(blob_hash=known_hash).first()
            if blob:
                db.delete(blob)
                db.commit()
        finally:
            db.close()
