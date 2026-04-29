import secrets

from sqlalchemy.orm import Session

from app.core.security import get_password_hash
from app.models.user import User


def get_by_email(db: Session, email: str) -> User | None:
    return db.query(User).filter(User.email == email).first()


def get_by_username(db: Session, username: str) -> User | None:
    return db.query(User).filter(User.username == username).first()


def get_by_uid(db: Session, uid: str) -> User | None:
    return db.query(User).filter(User.uid == uid).first()


def _generate_uid(db: Session) -> str:
    while True:
        candidate = f"USR-{secrets.token_hex(4).upper()}"
        if get_by_uid(db, candidate) is None:
            return candidate


def create(
    db: Session,
    *,
    username: str,
    email: str,
    password: str,
    user_type: str = "CONSUMER",
) -> User:
    user = User(
        uid=_generate_uid(db),
        username=username,
        email=email,
        hashed_password=get_password_hash(password),
        user_type=user_type,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
