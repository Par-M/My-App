from sqlalchemy import select

from app.db.database import SessionLocal
from app.models.auth_session import AuthSession
from app.models.user import User
from app.security.jwt import create_access_token
from app.security.jwt import create_refresh_token
from app.security.jwt import verify_token
from app.services.auth_service import AuthService

DEV_LOGIN = {"name": "Parthiv", "email": "parthiv@example.com"}


def _login(client, payload=None):
    response = client.post("/api/v1/auth/dev", json=payload or DEV_LOGIN)
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
    def test_logout_requires_authentication(self, client):
        response = client.post("/api/v1/auth/logout")
        assert response.status_code == 401

    def test_logout_revokes_all_sessions(self, client):
        data = _login(client)

        response = client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {data['access_token']}"},
        )
        assert response.status_code == 200

        # The refresh token that was valid a moment ago must now be rejected.
        refreshed = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        )
        assert refreshed.status_code == 401

    def test_logout_with_refresh_token_revokes_that_session(self, client):
        data = _login(client)

        response = client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {data['access_token']}"},
            json={"refresh_token": data["refresh_token"]},
        )
        assert response.status_code == 200

        refreshed = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        )
        assert refreshed.status_code == 401

    def test_logout_cannot_revoke_another_users_session(self, client):
        first = _login(client)
        second = _login(
            client,
            {"name": "Other", "email": "other@example.com"},
        )

        # Signed in as `second`, try to revoke `first`'s session.
        response = client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {second['access_token']}"},
            json={"refresh_token": first["refresh_token"]},
        )
        assert response.status_code == 200

        still_valid = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": first["refresh_token"]},
        )
        assert still_valid.status_code == 200


class TestRefreshRotation:
    def test_old_refresh_token_is_single_use(self, client):
        data = _login(client)

        first_refresh = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        )
        assert first_refresh.status_code == 200

        # Replaying the token that was just rotated must fail.
        replay = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        )
        assert replay.status_code == 401

    def test_reuse_detection_revokes_every_session(self, client):
        data = _login(client)

        rotated = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        ).json()

        # The legitimate holder of the newest token is signed out too, because
        # we cannot tell them apart from whoever replayed the old token.
        reuse = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        )
        assert reuse.status_code == 401

        newest = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": rotated["refresh_token"]},
        )
        assert newest.status_code == 401

    def test_rotation_chain_keeps_working(self, client):
        data = _login(client)
        token = data["refresh_token"]

        for _ in range(5):
            response = client.post(
                "/api/v1/auth/refresh", json={"refresh_token": token}
            )
            assert response.status_code == 200
            token = response.json()["refresh_token"]

    def test_expired_refresh_token_rejected(self, client, monkeypatch):
        from app.core.config import settings

        data = _login(client)
        monkeypatch.setattr(settings, "refresh_token_expire_days", -1)
        # Issue a new pair under the already-negative expiry.
        stale = _login(
            client, {"name": "Parthiv", "email": "parthiv@example.com"}
        )

        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": stale["refresh_token"]},
        )
        assert response.status_code == 401

    def test_access_token_rejected_as_refresh_token(self, client):
        data = _login(client)
        response = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["access_token"]},
        )
        assert response.status_code == 401


class TestAuthSessions:
    def test_login_creates_one_active_session(self, client):
        data = _login(client)

        with SessionLocal() as db:
            service = AuthService(db)
            assert service.active_session_count(data["user"]["id"]) == 1

    def test_rotation_revokes_the_previous_session(self, client):
        data = _login(client)

        client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        )

        with SessionLocal() as db:
            service = AuthService(db)
            # One row, revoked, plus the new one.
            assert service.active_session_count(data["user"]["id"]) == 1

    def test_rotated_session_records_its_replacement(self, client):
        data = _login(client)

        rotated = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": data["refresh_token"]},
        ).json()

        with SessionLocal() as db:
            from app.security.jwt import decode_token

            old_jti = decode_token(data["refresh_token"], "refresh")["jti"]
            new_jti = decode_token(rotated["refresh_token"], "refresh")["jti"]

            old = db.get(AuthSession, old_jti)
            assert old is not None
            assert old.revoked_at is not None
            assert old.replaced_by_jti == new_jti


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
