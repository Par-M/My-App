import uuid

from pydantic import BaseModel
from pydantic import EmailStr


class GoogleLoginRequest(BaseModel):
    id_token: str


class DevLoginRequest(BaseModel):
    name: str
    email: EmailStr


class RefreshRequest(BaseModel):
    refresh_token: str


class UserOut(BaseModel):
    id: uuid.UUID
    email: str | None
    name: str | None
    provider: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    user: UserOut
