"""Container startup workflow for local frontend/backend integration."""

import os
import subprocess
import time
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import OperationalError

from app.core.config import settings
from app.core.security import get_password_hash
from app.db.session import SessionLocal, engine
from app.models.user import User


DEMO_USER_ID = UUID("00000000-0000-0000-0000-000000000001")
DEMO_USERNAME = "demo_user"
DEMO_EMAIL = "demo@example.com"
DEMO_PASSWORD = "demo123456"
DB_WAIT_TIMEOUT_SECONDS = 60
DB_RETRY_INTERVAL_SECONDS = 2


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
    ensure_demo_user()
    ensure_storage_path()
    start_server()


if __name__ == "__main__":
    main()
