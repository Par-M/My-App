import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.user import User
from app.schemas.auth import TokenResponse
from app.schemas.auth import UserOut
from app.security.jwt import TOKEN_TYPE_REFRESH
from app.security.jwt import create_access_token
from app.security.jwt import create_refresh_token
from app.security.jwt import verify_token
from app.services.google import verify_google_id_token

PROVIDER_GOOGLE = "google"
PROVIDER_DEV = "dev"


class AuthService:
    def __init__(self, db: Session):
        self.db = db

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

    def refresh(self, refresh_token: str) -> TokenResponse:
        user_id = verify_token(refresh_token, TOKEN_TYPE_REFRESH)
        user = self._get_user(user_id)
        if user is None:
            raise ValueError("Invalid token")
        return self._issue_tokens(user)

    def _issue_tokens(self, user: User) -> TokenResponse:
        return TokenResponse(
            access_token=create_access_token(user.id),
            refresh_token=create_refresh_token(user.id),
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
