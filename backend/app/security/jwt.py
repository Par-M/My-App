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
    jti: str | None = None,
) -> tuple[str, str]:
    """Return ``(token, jti)``.

    The ``jti`` is returned as well as embedded so callers can persist a
    server-side session row keyed by it.
    """
    now = datetime.now(timezone.utc)
    token_jti = jti or str(uuid4())
    claims = {
        "sub": str(subject),
        "type": token_type,
        "iat": now,
        "exp": now + expires_delta,
        "jti": token_jti,
    }
    token = jwt.encode(claims, settings.jwt_secret, algorithm=ALGORITHM)
    return token, token_jti


def create_access_token(subject: str) -> str:
    token, _ = _create_token(
        subject,
        TOKEN_TYPE_ACCESS,
        timedelta(minutes=settings.access_token_expire_minutes),
    )
    return token


def create_refresh_token(subject: str, jti: str | None = None) -> str:
    token, _ = _create_token(
        subject,
        TOKEN_TYPE_REFRESH,
        timedelta(days=settings.refresh_token_expire_days),
        jti=jti,
    )
    return token


def decode_token(token: str, token_type: str) -> dict:
    """Verify a token and return its claims.

    Raises:
        ValueError: if the token is invalid or is of the wrong type.
    """
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except JWTError:
        raise ValueError("Invalid token")

    if payload.get("type") != token_type:
        raise ValueError("Invalid token type")

    if not payload.get("sub"):
        raise ValueError("Invalid token")

    if not payload.get("jti"):
        raise ValueError("Invalid token")

    return payload


def verify_token(token: str, token_type: str) -> str:
    return decode_token(token, token_type)["sub"]
