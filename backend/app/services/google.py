from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app.core.config import settings


class GoogleTokenVerificationError(Exception):
    pass


def verify_google_id_token(id_token: str) -> dict:
    if not settings.google_client_id:
        raise GoogleTokenVerificationError(
            "GOOGLE_CLIENT_ID is not configured"
        )

    try:
        return google_id_token.verify_oauth2_token(
            id_token,
            google_requests.Request(),
            audience=settings.google_client_id,
        )
    except ValueError as exc:
        raise GoogleTokenVerificationError(str(exc)) from exc
