from datetime import datetime
from datetime import timedelta
from datetime import timezone
from uuid import uuid4

from jose import JWTError
from jose import jwt

from app.core.config import settings

ALGORITHM = "HS256"

TOKEN_TYPE_ACCESS = "access"
TOKEN_TYPE_REFRESH = "refresh"


def _create_token(
    subject: str,
    token_type: str,
    expires_delta: timedelta,
) -> str:
    now = datetime.now(timezone.utc)
    claims = {
        "sub": str(subject),
        "type": token_type,
        "iat": now,
        "exp": now + expires_delta,
        "jti": str(uuid4()),
    }
    return jwt.encode(claims, settings.jwt_secret, algorithm=ALGORITHM)


def create_access_token(subject: str) -> str:
    return _create_token(
        subject,
        TOKEN_TYPE_ACCESS,
        timedelta(minutes=settings.access_token_expire_minutes),
    )


def create_refresh_token(subject: str) -> str:
    return _create_token(
        subject,
        TOKEN_TYPE_REFRESH,
        timedelta(days=settings.refresh_token_expire_days),
    )


def verify_token(token: str, token_type: str) -> str:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except JWTError:
        raise ValueError("Invalid token")

    if payload.get("type") != token_type:
        raise ValueError("Invalid token type")

    subject = payload.get("sub")
    if not subject:
        raise ValueError("Invalid token")

    return subject
