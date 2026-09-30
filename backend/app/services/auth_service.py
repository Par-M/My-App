import uuid
from datetime import datetime
from datetime import timedelta
from datetime import timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.auth_session import AuthSession
from app.models.user import User
from app.schemas.auth import TokenResponse
from app.schemas.auth import UserOut
from app.security.jwt import TOKEN_TYPE_REFRESH
from app.security.jwt import create_access_token
from app.security.jwt import create_refresh_token
from app.security.jwt import decode_token
from app.security.jwt import verify_token
from app.services.google import verify_google_id_token

PROVIDER_GOOGLE = "google"
PROVIDER_DEV = "dev"

REVOKED_ROTATED = "rotated"
REVOKED_LOGOUT = "logout"
REVOKED_REUSE = "reuse_detected"
REVOKED_EXPIRED = "expired"


def _now() -> datetime:
    return datetime.now(timezone.utc)


class AuthError(ValueError):
    """Authentication failed. Always surfaced to the client as a 401."""


class AuthService:
    def __init__(self, db: Session):
        self.db = db

    # ------------------------------------------------------------------
    # Login
    # ------------------------------------------------------------------

    def login_with_google(self, id_token: str) -> TokenResponse:
        info = verify_google_id_token(id_token)
        user = self._find_or_create_user(
            provider=PROVIDER_GOOGLE,
            provider_user_id=str(info.get("sub")),
            email=info.get("email"),
            name=info.get("name"),
        )
        return self._issue_tokens(user)

    def login_dev(self, name: str, email: str) -> TokenResponse:
        user = self._find_or_create_user(
            provider=PROVIDER_DEV,
            provider_user_id=email,
            email=email,
            name=name,
        )
        return self._issue_tokens(user)

    # ------------------------------------------------------------------
    # Refresh
    # ------------------------------------------------------------------

    def refresh(self, refresh_token: str) -> TokenResponse:
        """Rotate a refresh token.

        The presented token is single use: it is revoked and linked to its
        replacement. Presenting one that was already rotated means it leaked, so
        every session for that user is revoked.
        """
        try:
            claims = decode_token(refresh_token, TOKEN_TYPE_REFRESH)
        except ValueError as exc:
            raise AuthError(str(exc)) from exc

        jti = claims["jti"]
        user = self._get_user(claims["sub"])
        if user is None:
            raise AuthError("Invalid token")

        session = self.db.get(AuthSession, jti)
        if session is None:
            # Correctly signed but unknown. Either the row was deleted or the
            # signing secret is compromised. Reject without revoking the user's
            # other sessions, which would let anyone force a mass sign-out.
            raise AuthError("Invalid token")

        if session.user_id != user.id:
            raise AuthError("Invalid token")

        if session.revoked_at is not None:
            self._revoke_all_for_user(
                user.id, reason=REVOKED_REUSE, except_jti=session.jti
            )
            self.db.commit()
            raise AuthError("Refresh token has already been used")

        if session.expires_at <= _now():
            session.revoked_at = _now()
            session.revoked_reason = REVOKED_EXPIRED
            self.db.commit()
            raise AuthError("Refresh token has expired")

        # Rotate: revoke this row, then issue and link a fresh one.
        response = self._issue_tokens(user, previous_jti=session.jti)
        return response

    # ------------------------------------------------------------------
    # Logout
    # ------------------------------------------------------------------

    def logout(
        self,
        user: User,
        refresh_token: str | None = None,
    ) -> None:
        """Revoke the caller's sessions.

        With a refresh token, only that session is revoked. Without one, every
        session for the user is revoked, which is what signing out of the
        device is expected to mean.
        """
        if refresh_token:
            try:
                claims = decode_token(refresh_token, TOKEN_TYPE_REFRESH)
            except ValueError as exc:
                raise AuthError(str(exc)) from exc
            session = self.db.get(AuthSession, claims["jti"])
            if session is not None and session.user_id == user.id:
                self._revoke(session, REVOKED_LOGOUT)
        else:
            self._revoke_all_for_user(user.id, reason=REVOKED_LOGOUT)
        self.db.commit()

    def _revoke(self, session: AuthSession, reason: str) -> None:
        if session.revoked_at is None:
            session.revoked_at = _now()
            session.revoked_reason = reason

    def _revoke_all_for_user(
        self,
        user_id: uuid.UUID,
        reason: str,
        except_jti: str | None = None,
    ) -> int:
        statement = select(AuthSession).where(
            AuthSession.user_id == user_id,
            AuthSession.revoked_at.is_(None),
        )
        if except_jti is not None:
            statement = statement.where(AuthSession.jti != except_jti)

        count = 0
        for session in self.db.scalars(statement).all():
            self._revoke(session, reason)
            count += 1
        return count

    def active_session_count(self, user_id: uuid.UUID) -> int:
        return len(
            list(
                self.db.scalars(
                    select(AuthSession).where(
                        AuthSession.user_id == user_id,
                        AuthSession.revoked_at.is_(None),
                    )
                ).all()
            )
        )

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _issue_tokens(
        self,
        user: User,
        previous_jti: str | None = None,
    ) -> TokenResponse:
        expires_at = _now() + timedelta(days=settings.refresh_token_expire_days)
        session = AuthSession(
            user_id=user.id,
            expires_at=expires_at,
        )
        self.db.add(session)
        self.db.flush()  # populates session.jti from the default

        access_token = create_access_token(user.id)
        refresh_token = create_refresh_token(user.id, jti=session.jti)

        if previous_jti is not None:
            previous = self.db.get(AuthSession, previous_jti)
            if previous is not None:
                self._revoke(previous, REVOKED_ROTATED)
                previous.replaced_by_jti = session.jti

        self.db.commit()
        self.db.refresh(session)

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            user=self._to_user_out(user),
        )

    def _find_or_create_user(
        self,
        provider: str,
        provider_user_id: str,
        email: str | None,
        name: str | None,
    ) -> User:
        user = self.db.scalar(
            select(User).where(
                User.provider == provider,
                User.provider_user_id == provider_user_id,
            )
        )
        if user is not None:
            return user

        user = User(
            provider=provider,
            provider_user_id=provider_user_id,
            email=email,
            name=name,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user

    def _get_user(self, user_id: str) -> User | None:
        try:
            parsed = uuid.UUID(user_id)
        except ValueError:
            return None
        return self.db.get(User, parsed)

    def _to_user_out(self, user: User) -> UserOut:
        return UserOut(
            id=user.id,
            email=user.email,
            name=user.name,
            provider=user.provider,
        )


# Re-exported so callers that only imported the old helper keep working.
__all__ = ["AuthError", "AuthService", "create_refresh_token", "verify_token"]
