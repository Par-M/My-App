from sqlalchemy import select

from app.db.database import SessionLocal
from app.models.user import User
from app.security.jwt import create_access_token
from app.security.jwt import create_refresh_token
from app.security.jwt import verify_token

DEV_LOGIN = {"name": "Parthiv", "email": "parthiv@example.com"}


def _login(client):
    response = client.post("/api/v1/auth/dev", json=DEV_LOGIN)
    assert response.status_code == 200
    return response.json()


def _users_in_db():
    with SessionLocal() as db:
        return list(db.scalars(select(User)))


class TestDevLogin:
    def test_new_user_sign_in_creates_account(self, client):
        data = _login(client)

        assert data["access_token"]
        assert data["refresh_token"]
        assert data["user"]["provider"] == "dev"
        assert data["user"]["email"] == DEV_LOGIN["email"]

        users = _users_in_db()
        assert len(users) == 1
        assert users[0].provider == "dev"
        assert users[0].email == DEV_LOGIN["email"]

    def test_returning_user_reuses_existing_account(self, client):
        first = _login(client)
        second = _login(client)

        users = _users_in_db()
        assert len(users) == 1
        assert first["user"]["id"] == second["user"]["id"]

    def test_dev_auth_disabled_returns_404(self, client, monkeypatch):
        from app.core.config import settings

        monkeypatch.setattr(settings, "enable_dev_auth", False)
        response = client.post("/api/v1/auth/dev", json=DEV_LOGIN)
        assert response.status_code == 404


class TestGoogleLogin:
    def test_invalid_google_token_rejected(self, client):
        response = client.post(
            "/api/v1/auth/google",
            json={"id_token": "not-a-real-token"},
        )
        assert response.status_code == 401


class TestProtectedEndpoint:
    def test_me_requires_token(self, client):
        response = client.get("/api/v1/auth/me")
        assert response.status_code == 401

    def test_me_rejects_invalid_token(self, client):
        response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": "Bearer garbage"},
        )
        assert response.status_code == 401

    def test_me_succeeds_with_valid_token(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {data['access_token']}"},
        )
        assert response.status_code == 200
        assert response.json()["email"] == DEV_LOGIN["email"]

    def test_me_rejects_expired_access_token(self, client, monkeypatch):
        from app.core.config import settings

        data = _login(client)
        monkeypatch.setattr(settings, "access_token_expire_minutes", -1)
        expired = create_access_token(data["user"]["id"])

        response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {expired}"},
        )
        assert response.status_code == 401


class TestRefresh:
    def test_expired_access_token_can_be_refreshed(self, client, monkeypatch):
        from app.core.config import settings

        data = _login(client)
        monkeypatch.setattr(settings, "access_token_expire_minutes", -1)
        expired = create_access_token(data["user"]["id"])

        denied = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {expired}"},
        )
        assert denied.status_code == 401

        refreshed = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        )
        assert refreshed.status_code == 200
        assert refreshed.json()["access_token"] != expired

    def test_invalid_refresh_token_rejected(self, client):
        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": "garbage"},
        )
        assert response.status_code == 401

    def test_access_token_rejected_as_refresh_token(self, client):
        data = _login(client)
        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["access_token"]},
        )
        assert response.status_code == 401

    def test_refresh_rotates_tokens(self, client):
        data = _login(client)
        refreshed = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        ).json()

        assert refreshed["refresh_token"] != data["refresh_token"]
        assert refreshed["access_token"] != data["access_token"]


class TestLogout:
    def test_logout_returns_success(self, client):
        response = client.post("/api/v1/auth/logout")
        assert response.status_code == 200


class TestJWT:
    def test_tokens_verify_with_matching_type(self):
        subject = "123"
        access = create_access_token(subject)
        refresh = create_refresh_token(subject)

        assert verify_token(access, "access") == subject
        assert verify_token(refresh, "refresh") == subject

    def test_verify_rejects_mismatched_type(self):
        import pytest

        access = create_access_token("123")
        with pytest.raises(ValueError):
            verify_token(access, "refresh")
