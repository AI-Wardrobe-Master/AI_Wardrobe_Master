#!/usr/bin/env python3
"""Seed outfit-agent test clothing into the local backend database."""

import argparse
import asyncio
import hashlib
import io
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import settings  # noqa: E402
from app.crud import user as crud_user  # noqa: E402
from app.crud.wardrobe import ensure_item_in_main_wardrobe  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.models.clothing_item import ClothingItem, Image  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services.blob_service import BlobService  # noqa: E402


DEFAULT_EMAIL = "00001@gmail.com"
EXPECTED_ITEM_COUNT = 30
IMAGE_TYPE = "PROCESSED_FRONT"
AGENT_SEED_TAG = "agent_seed"


@dataclass
class SeedStats:
    """Counters describing one seed run."""

    created: int = 0
    updated: int = 0
    image_created: int = 0
    image_updated: int = 0
    image_unchanged: int = 0
    wardrobe_linked: int = 0


def parse_args() -> argparse.Namespace:
    """Parse command line arguments for the seed script.

    Returns:
        Parsed argparse namespace with paths and user options.
    """
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Seed agent test clothing images and metadata."
    )
    parser.add_argument("--email", default=DEFAULT_EMAIL)
    parser.add_argument(
        "--seed-json",
        type=Path,
        default=repo_root / "test" / "clothing" / "clothing_seed.json",
    )
    parser.add_argument(
        "--images-dir",
        type=Path,
        default=repo_root / "test" / "clothing" / "images_no_bg",
    )
    parser.add_argument(
        "--create-user",
        action="store_true",
        help="Create the target user when the email is missing.",
    )
    parser.add_argument(
        "--password",
        help="Password for --create-user. Required only when creating the user.",
    )
    parser.add_argument(
        "--expected-count",
        type=int,
        default=EXPECTED_ITEM_COUNT,
        help="Expected number of seed items and PNG files.",
    )
    return parser.parse_args()


def load_seed_items(seed_json: Path) -> list[dict[str, Any]]:
    """Load seed metadata from JSON.

    Args:
        seed_json: Path to the seed metadata JSON file.

    Returns:
        List of item dictionaries from the JSON document.

    Raises:
        ValueError: If the file is malformed or has no items list.
    """
    with seed_json.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    items = payload.get("items")
    if not isinstance(items, list):
        raise ValueError(f"{seed_json} must contain an items list")
    return items


def validate_seed_files(
    items: list[dict[str, Any]],
    images_dir: Path,
    expected_count: int,
) -> None:
    """Validate seed item count and filename-to-PNG correspondence.

    Args:
        items: Seed item dictionaries.
        images_dir: Directory containing no-background PNG files.
        expected_count: Expected item and PNG count.

    Raises:
        ValueError: If counts, required fields, or image files do not match.
    """
    if len(items) != expected_count:
        raise ValueError(f"Expected {expected_count} items, found {len(items)}")
    if not images_dir.is_dir():
        raise ValueError(f"Images directory does not exist: {images_dir}")

    ids = [item.get("id") for item in items]
    filenames = [item.get("localFilename") for item in items]
    if any(not value or not isinstance(value, str) for value in ids):
        raise ValueError("Every seed item must have a string id")
    if any(not value or not isinstance(value, str) for value in filenames):
        raise ValueError("Every seed item must have a string localFilename")
    if len(set(ids)) != len(ids):
        raise ValueError("Seed item ids must be unique")
    if len(set(filenames)) != len(filenames):
        raise ValueError("Seed localFilename values must be unique")

    expected_names = set(filenames)
    actual_names = {path.name for path in images_dir.glob("*.png")}
    missing = sorted(expected_names - actual_names)
    extra = sorted(actual_names - expected_names)
    if missing:
        raise ValueError(f"Missing PNG files: {', '.join(missing)}")
    if extra:
        raise ValueError(f"Unexpected PNG files: {', '.join(extra)}")
    if len(actual_names) != expected_count:
        raise ValueError(f"Expected {expected_count} PNG files, found {len(actual_names)}")

    required_fields = ("name", "category", "material", "style", "finalTags")
    for item in items:
        for field in required_fields:
            if field not in item:
                raise ValueError(f"Seed item {item['id']} is missing {field}")
        if not isinstance(item["finalTags"], list):
            raise ValueError(f"Seed item {item['id']} finalTags must be a list")


def get_or_create_user(
    db: Session,
    *,
    email: str,
    create_user: bool,
    password: str | None,
) -> User:
    """Fetch the target user by email or create it when explicitly requested.

    Args:
        db: Active SQLAlchemy session.
        email: Target account email.
        create_user: Whether a missing user may be created.
        password: Password for user creation.

    Returns:
        Existing or newly created user.

    Raises:
        ValueError: If the user is missing and creation was not fully requested.
    """
    user = crud_user.get_by_email(db, email)
    if user is not None:
        return user
    if not create_user:
        raise ValueError(
            f"User email {email!r} does not exist. Re-run with "
            "--create-user --password <password> if this test account should be created."
        )
    if not password:
        raise ValueError("--password is required with --create-user")

    username = email.split("@", 1)[0]
    existing_username = crud_user.get_by_username(db, username)
    if existing_username is not None:
        username = f"{username}_agent_seed"
    return crud_user.create(
        db,
        username=username,
        email=email,
        password=password,
        user_type="CONSUMER",
    )


def seed_id_tag(seed_id: str) -> str:
    """Build the custom tag used to identify one seed item.

    Args:
        seed_id: Item id from the seed JSON.

    Returns:
        Stable custom tag string for idempotent lookup.
    """
    return f"seed_id:{seed_id}"


def merge_custom_tags(existing_tags: list[str] | None, seed_id: str) -> list[str]:
    """Merge existing custom tags with required agent seed tags.

    Args:
        existing_tags: Current item custom tags.
        seed_id: Item id from the seed JSON.

    Returns:
        Ordered, de-duplicated custom tags.
    """
    merged: list[str] = []
    seen: set[str] = set()
    for tag in [*(existing_tags or []), AGENT_SEED_TAG, seed_id_tag(seed_id)]:
        normalized = str(tag).strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        merged.append(normalized)
    return merged


def file_sha256(path: Path) -> str:
    """Calculate the SHA-256 hash of a local file.

    Args:
        path: File path to hash.

    Returns:
        Hexadecimal SHA-256 digest.
    """
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def find_seed_item(db: Session, *, user_id: Any, seed_id: str) -> ClothingItem | None:
    """Find an existing clothing item for one seed id.

    Args:
        db: Active SQLAlchemy session.
        user_id: Target user UUID.
        seed_id: Item id from the seed JSON.

    Returns:
        Existing clothing item or None.

    Raises:
        ValueError: If more than one active item matches the same seed id.
    """
    matches = (
        db.query(ClothingItem)
        .filter(
            ClothingItem.user_id == user_id,
            ClothingItem.deleted_at.is_(None),
            ClothingItem.custom_tags.any(AGENT_SEED_TAG),
            ClothingItem.custom_tags.any(seed_id_tag(seed_id)),
        )
        .all()
    )
    if len(matches) > 1:
        raise ValueError(f"Multiple clothing items already match seed id {seed_id}")
    return matches[0] if matches else None


def upsert_clothing_item(
    db: Session,
    *,
    user_id: Any,
    seed_item: dict[str, Any],
    stats: SeedStats,
) -> ClothingItem:
    """Create or update the clothing item row for one seed item.

    Args:
        db: Active SQLAlchemy session.
        user_id: Target user UUID.
        seed_item: Seed item metadata.
        stats: Mutable run counters.

    Returns:
        Created or updated clothing item.
    """
    item = find_seed_item(db, user_id=user_id, seed_id=seed_item["id"])
    if item is None:
        item = ClothingItem(user_id=user_id)
        db.add(item)
        stats.created += 1
    else:
        stats.updated += 1

    # Keep metadata in sync with the canonical seed JSON on every run.
    item.source = "OWNED"
    item.is_confirmed = True
    item.name = seed_item["name"]
    item.description = seed_item.get("description")
    item.category = seed_item["category"]
    item.material = seed_item["material"]
    item.style = seed_item["style"]
    item.final_tags = seed_item["finalTags"]
    item.predicted_tags = item.predicted_tags or []
    item.custom_tags = merge_custom_tags(item.custom_tags, seed_item["id"])
    db.flush()
    return item


async def upsert_processed_front_image(
    db: Session,
    *,
    item: ClothingItem,
    image_path: Path,
    blob_service: BlobService,
    stats: SeedStats,
) -> None:
    """Create or update the processed-front image for one clothing item.

    Args:
        db: Active SQLAlchemy session.
        item: Clothing item that owns the image.
        image_path: Local PNG file path.
        blob_service: Blob service used for database-backed ingest.
        stats: Mutable run counters.
    """
    expected_hash = file_sha256(image_path)
    image = (
        db.query(Image)
        .filter(
            Image.clothing_item_id == item.id,
            Image.image_type == IMAGE_TYPE,
            Image.angle.is_(None),
        )
        .first()
    )
    if image is not None and image.blob_hash == expected_hash:
        stats.image_unchanged += 1
        return

    # Ingest only when the row is missing or points at different content.
    old_blob_hash = image.blob_hash if image is not None else None
    with image_path.open("rb") as handle:
        data = io.BytesIO(handle.read())
    blob = await blob_service.ingest_upload(
        db,
        data,
        claimed_mime_type="image/png",
        max_size=settings.MAX_UPLOAD_SIZE_BYTES,
    )
    if image is None:
        db.add(
            Image(
                clothing_item_id=item.id,
                image_type=IMAGE_TYPE,
                blob_hash=blob.blob_hash,
                angle=None,
            )
        )
        stats.image_created += 1
    else:
        image.blob_hash = blob.blob_hash
        stats.image_updated += 1

    db.flush()
    if old_blob_hash and old_blob_hash != blob.blob_hash:
        blob_service.release(db, old_blob_hash)


async def seed_agent_clothing(args: argparse.Namespace) -> SeedStats:
    """Run the clothing seed workflow.

    Args:
        args: Parsed command line arguments.

    Returns:
        Counters for created, updated, and image rows.
    """
    items = load_seed_items(args.seed_json)
    validate_seed_files(items, args.images_dir, args.expected_count)
    blob_service = BlobService()
    stats = SeedStats()

    with SessionLocal() as db:
        user = get_or_create_user(
            db,
            email=args.email,
            create_user=args.create_user,
            password=args.password,
        )
        for seed_item in items:
            image_path = args.images_dir / seed_item["localFilename"]
            item = upsert_clothing_item(
                db,
                user_id=user.id,
                seed_item=seed_item,
                stats=stats,
            )
            await upsert_processed_front_image(
                db,
                item=item,
                image_path=image_path,
                blob_service=blob_service,
                stats=stats,
            )
            ensure_item_in_main_wardrobe(
                db,
                user_id=user.id,
                clothing_item_id=item.id,
            )
            stats.wardrobe_linked += 1
            db.commit()

    return stats


def print_stats(stats: SeedStats) -> None:
    """Print seed counters in a stable format.

    Args:
        stats: Run counters to display.
    """
    print(
        "Seed complete: "
        f"created={stats.created} updated={stats.updated} "
        f"image_created={stats.image_created} "
        f"image_updated={stats.image_updated} "
        f"image_unchanged={stats.image_unchanged} "
        f"wardrobe_linked={stats.wardrobe_linked}"
    )


def main() -> int:
    """Script entrypoint.

    Returns:
        Process exit code.
    """
    args = parse_args()
    try:
        stats = asyncio.run(seed_agent_clothing(args))
    except OperationalError as exc:
        print(f"Database connection failed: {exc}", file=sys.stderr)
        print(
            "Start the local backend database with: docker compose up --build",
            file=sys.stderr,
        )
        return 2
    except Exception as exc:
        print(f"Seed failed: {exc}", file=sys.stderr)
        return 1
    print_stats(stats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
