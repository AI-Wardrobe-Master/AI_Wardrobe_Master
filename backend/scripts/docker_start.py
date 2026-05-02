"""Container startup workflow for local frontend/backend integration."""

import os
import shutil
import subprocess
import time
from pathlib import Path
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import OperationalError

from app.core.config import settings
from app.core.security import get_password_hash
from app.db.session import SessionLocal, engine
from app.models.creator import CreatorProfile
from app.models.user import User


DEMO_USER_ID = UUID("00000000-0000-0000-0000-000000000001")
DEMO_USERNAME = "demo_user"
DEMO_EMAIL = "demo@example.com"
DEMO_PASSWORD = "demo123456"
DEMO_CREATOR_DISPLAY_NAME = "Demo Creator"
DEMO_CREATOR_BRAND_NAME = "Demo Brand"
DEMO_CREATOR_BIO = "Seed creator profile for local Docker integration."
DB_WAIT_TIMEOUT_SECONDS = 60
DB_RETRY_INTERVAL_SECONDS = 2
DEMO_DATA_DIR = Path(__file__).resolve().parents[1] / "demo_data"
DEMO_SQL_PATH = DEMO_DATA_DIR / "demo_snapshot.sql"
DEMO_STORAGE_PATH = DEMO_DATA_DIR / "storage"


def wait_for_database() -> None:
    deadline = time.time() + DB_WAIT_TIMEOUT_SECONDS

    while time.time() < deadline:
        try:
            with engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            print("Database connection is ready.", flush=True)
            return
        except OperationalError:
            print("Waiting for database...", flush=True)
            time.sleep(DB_RETRY_INTERVAL_SECONDS)

    raise RuntimeError(
        f"Database was not ready within {DB_WAIT_TIMEOUT_SECONDS} seconds."
    )


def run_migrations() -> None:
    print("Applying Alembic migrations...", flush=True)
    subprocess.run(["alembic", "upgrade", "head"], check=True)


def _table_count(table_name: str) -> int:
    with engine.connect() as connection:
        result = connection.execute(text(f"SELECT COUNT(*) FROM {table_name}"))
        return int(result.scalar_one())


def maybe_restore_demo_snapshot() -> None:
    """Restore bundled demo records and blobs for fresh local Docker installs."""
    if not DEMO_SQL_PATH.exists():
        print("No bundled demo snapshot found; skipping demo restore.", flush=True)
        return

    existing_wardrobes = _table_count("wardrobes")
    existing_clothes = _table_count("clothing_items")
    if existing_wardrobes > 0 or existing_clothes > 0:
        print("Existing wardrobe data found; skipping bundled demo restore.", flush=True)
        return

    print("Restoring bundled demo database snapshot...", flush=True)
    env = os.environ.copy()
    env["PGPASSWORD"] = settings.POSTGRES_PASSWORD
    subprocess.run(
        [
            "psql",
            "-h",
            settings.POSTGRES_SERVER,
            "-p",
            str(settings.POSTGRES_PORT),
            "-U",
            settings.POSTGRES_USER,
            "-d",
            settings.POSTGRES_DB,
            "-v",
            "ON_ERROR_STOP=1",
            "-f",
            str(DEMO_SQL_PATH),
        ],
        check=True,
        env=env,
    )

    if DEMO_STORAGE_PATH.exists():
        print("Restoring bundled demo media and 3D assets...", flush=True)
        shutil.copytree(
            DEMO_STORAGE_PATH,
            settings.LOCAL_STORAGE_PATH,
            dirs_exist_ok=True,
        )


def ensure_demo_user() -> None:
    print("Ensuring seed user exists...", flush=True)
    with SessionLocal() as session:
        existing_user = session.get(User, DEMO_USER_ID)
        if existing_user is not None:
            existing_user.username = DEMO_USERNAME
            existing_user.email = DEMO_EMAIL
            existing_user.hashed_password = get_password_hash(DEMO_PASSWORD)
            existing_user.user_type = "CONSUMER"
            existing_user.is_active = True
            session.commit()
            return

        session.add(
            User(
                id=DEMO_USER_ID,
                username=DEMO_USERNAME,
                email=DEMO_EMAIL,
                hashed_password=get_password_hash(DEMO_PASSWORD),
                user_type="CONSUMER",
                is_active=True,
            )
        )
        session.commit()
    print(
        f"Seed user ready: email={DEMO_EMAIL} password={DEMO_PASSWORD}",
        flush=True,
    )


def ensure_demo_creator_profile() -> None:
    print("Ensuring demo creator profile exists...", flush=True)
    with SessionLocal() as session:
        profile = session.get(CreatorProfile, DEMO_USER_ID)
        if profile is not None:
            profile.status = "ACTIVE"
            profile.display_name = DEMO_CREATOR_DISPLAY_NAME
            profile.brand_name = DEMO_CREATOR_BRAND_NAME
            profile.bio = DEMO_CREATOR_BIO
            profile.social_links = {}
            profile.is_verified = False
            session.commit()
            return

        session.add(
            CreatorProfile(
                user_id=DEMO_USER_ID,
                status="ACTIVE",
                display_name=DEMO_CREATOR_DISPLAY_NAME,
                brand_name=DEMO_CREATOR_BRAND_NAME,
                bio=DEMO_CREATOR_BIO,
                social_links={},
                is_verified=False,
            )
        )
        session.commit()
    print(
        f"Seed creator ready: user_id={DEMO_USER_ID} display_name={DEMO_CREATOR_DISPLAY_NAME}",
        flush=True,
    )


def ensure_storage_path() -> None:
    os.makedirs(settings.LOCAL_STORAGE_PATH, exist_ok=True)


def start_server() -> None:
    print("Starting FastAPI server...", flush=True)
    os.execvp(
        "uvicorn",
        ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"],
    )


def main() -> None:
    wait_for_database()
    run_migrations()
    maybe_restore_demo_snapshot()
    ensure_demo_user()
    ensure_demo_creator_profile()
    ensure_storage_path()
    start_server()


if __name__ == "__main__":
    main()
