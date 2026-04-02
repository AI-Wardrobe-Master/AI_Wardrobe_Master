"""API dependencies for DB sessions and authenticated users."""
from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.crud import creator as crud_creator
from app.db.session import get_db  # noqa: F401 - re-exported for Depends()
from app.models.user import User

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> UUID:
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise credentials_error

    token = credentials.credentials

    try:
        payload = decode_access_token(token)
        subject = payload.get("sub")
        if subject is None:
            raise credentials_error
        user_id = UUID(subject)
    except (JWTError, ValueError) as exc:
        raise credentials_error from exc

    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise credentials_error

    return user_id


def get_current_creator_user_id(
    user_id: UUID = Depends(get_current_user_id),
    db: Session = Depends(get_db),
) -> UUID:
    creator_profile = crud_creator.get_by_user_id(db, user_id)
    if creator_profile is None or creator_profile.status != "ACTIVE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Creator permission required",
        )
    return user_id
