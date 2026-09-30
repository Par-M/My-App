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

# Upper bound on how far we will walk a rotation chain forward for a token
# that was already rotated. Newer links are real tokens; an unbounded walk
# risks an attacker minting endless sessions from a single leaked token.
MAX_ROTATION_CHAIN_WALK = 10


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

        Rotation is serialized per token with a row lock so overlapping
        refreshes for the same token cannot race. A token that was already
        rotated is followed forward along its rotation chain to the current
        live session, which is rotated instead. This keeps a benign duplicate
        (for example two concurrent refreshes fired by the same device) from
        signing the user out everywhere: the whole chain stays usable until an
        explicit logout or expiry. Only a session that was explicitly revoked
        (logout) or expired refuses to refresh.
        """
        try:
            claims = decode_token(refresh_token, TOKEN_TYPE_REFRESH)
        except ValueError as exc:
            raise AuthError(str(exc)) from exc

        jti = claims["jti"]
        user = self._get_user(claims["sub"])
        if user is None:
            raise AuthError("Invalid token")

        session = self._locked_session(jti)
        if session is None:
            # Correctly signed but unknown. Either the row was deleted or the
            # signing secret is compromised. Reject without revoking the user's
            # other sessions, which would let anyone force a mass sign-out.
            raise AuthError("Invalid token")

        if session.user_id != user.id:
            raise AuthError("Invalid token")

        # Follow the rotation chain forward. The presented token may have been
        # rotated by a concurrent refresh that won the race; rotate whatever
        # live session the chain currently points at so every holder of a token
        # in the chain keeps a working session.
        current = session
        walk = 0
        while (
            current.revoked_at is not None
            and current.replaced_by_jti is not None
            and walk < MAX_ROTATION_CHAIN_WALK
        ):
            next_link = self._locked_session(current.replaced_by_jti)
            if next_link is None or next_link.user_id != user.id:
                break
            current = next_link
            walk += 1

        if current.user_id != user.id:
            raise AuthError("Invalid token")

        if current.revoked_at is not None:
            # The chain ends in a session that was explicitly revoked (logout)
            # rather than rotated. Do not resurrect it, and do not revoke the
            # user's other sessions either.
            raise AuthError("Refresh token has been revoked")

        if current.expires_at <= _now():
            self._revoke(current, REVOKED_EXPIRED)
            self.db.commit()
            raise AuthError("Refresh token has expired")

        # Rotate: revoke this row, then issue and link a fresh one.
        response = self._issue_tokens(user, previous_jti=current.jti)
        return response

    def _locked_session(self, jti: str) -> AuthSession | None:
        """Fetch a session row, locking it for the rest of this transaction.

        Serializes concurrent rotations of the same token so that overlapping
        refreshes cannot both read the row as active and diverge.
        """
        return self.db.scalar(
            select(AuthSession)
            .where(AuthSession.jti == jti)
            .with_for_update()
        )

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
        now = _now()
        expires_at = now + timedelta(days=settings.refresh_token_expire_days)
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
                previous.last_used_at = now
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
