from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.security import create_access_token, verify_password
from app.crud import user as crud_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import (
    AuthUser,
    LoginRequest,
    LoginResponse,
    LoginResponseData,
    RegisterRequest,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _build_login_response(user: User) -> LoginResponse:
    token = create_access_token(str(user.id))
    return LoginResponse(
        data=LoginResponseData(
            user=AuthUser(
                id=user.id,
                username=user.username,
                email=user.email,
                type=user.user_type,
                createdAt=user.created_at,
            ),
            token=token,
        )
    )


@router.post("/register", response_model=LoginResponse, status_code=status.HTTP_201_CREATED)
def register(body: RegisterRequest, db: Session = Depends(get_db)):
    if crud_user.get_by_email(db, body.email) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    if crud_user.get_by_username(db, body.username) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username already taken",
        )

    user = crud_user.create(
        db,
        username=body.username,
        email=body.email,
        password=body.password,
        user_type="CONSUMER",
    )
    return _build_login_response(user)


@router.post("/login", response_model=LoginResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email).first()
    if user is None or not verify_password(body.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Inactive user",
        )

    return _build_login_response(user)
