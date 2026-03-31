from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


VALID_USER_TYPES = {"CONSUMER", "CREATOR"}


class LoginRequest(BaseModel):
    email: str
    password: str


class RegisterRequest(BaseModel):
    username: str = Field(min_length=3, max_length=50)
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=8, max_length=255)
    user_type: str | None = Field(default=None, alias="userType")

    @field_validator("username")
    @classmethod
    def validate_username(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Username must not be empty")
        return value

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        value = value.strip().lower()
        local_part, separator, domain = value.partition("@")
        if not separator or not local_part or "." not in domain:
            raise ValueError("Invalid email address")
        return value

    @field_validator("user_type")
    @classmethod
    def validate_user_type(cls, value: str | None) -> str | None:
        if value is None:
            return value
        normalized = value.strip().upper()
        if normalized not in VALID_USER_TYPES:
            raise ValueError("Invalid user type")
        return normalized


class AuthUser(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: UUID
    username: str
    email: str
    user_type: str = Field(alias="type")
    created_at: datetime = Field(alias="createdAt")


class LoginResponseData(BaseModel):
    user: AuthUser
    token: str


class LoginResponse(BaseModel):
    success: bool = True
    data: LoginResponseData
