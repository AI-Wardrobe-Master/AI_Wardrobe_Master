#!/usr/bin/env python3
"""
Verify blob refcounts match actual references across all business tables.
Run: cd backend && python -m scripts.verify_blob_refcount

Does NOT auto-correct. Reports discrepancies for manual diagnosis.
"""

import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.models.blob import Blob  # noqa: E402
from sqlalchemy import text  # noqa: E402

REFERENCING_TABLES = [
    ("images", "blob_hash"),
    ("creator_item_images", "blob_hash"),
    ("models_3d", "blob_hash"),
    ("creator_models_3d", "blob_hash"),
    ("styled_generations", "selfie_original_blob_hash"),
    ("styled_generations", "selfie_processed_blob_hash"),
    ("styled_generations", "result_image_blob_hash"),
    ("outfit_preview_tasks", "person_image_blob_hash"),
    ("outfit_preview_tasks", "preview_image_blob_hash"),
    ("outfit_preview_task_items", "garment_image_blob_hash"),
    ("outfits", "preview_image_blob_hash"),
    ("card_packs", "cover_image_blob_hash"),
]


def main():
    db = SessionLocal()
    try:
        actual_counts: Counter = Counter()

        for table, column in REFERENCING_TABLES:
            rows = db.execute(
                text(f"SELECT {column} FROM {table} WHERE {column} IS NOT NULL")
            ).fetchall()
            for (blob_hash,) in rows:
                actual_counts[blob_hash] += 1

        blobs = db.query(Blob).all()
        issues = 0

        for blob in blobs:
            actual = actual_counts.get(blob.blob_hash, 0)
            if actual != blob.ref_count:
                print(
                    f"MISMATCH: blob={blob.blob_hash[:16]}... "
                    f"recorded={blob.ref_count} actual={actual}"
                )
                issues += 1

        for h, count in actual_counts.items():
            if not db.query(Blob).filter_by(blob_hash=h).first():
                print(f"ORPHAN REF: {h[:16]}... referenced {count}x but no blob row")
                issues += 1

        if issues == 0:
            print(f"OK: all {len(blobs)} blobs have correct refcounts")
        else:
            print(f"FOUND {issues} issue(s)")
            sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
