import uuid
from datetime import datetime
from datetime import timedelta
from datetime import timezone

from fastapi.testclient import TestClient


def _auth_headers(client: TestClient, *, email: str = "focus@test.dev") -> dict[str, str]:
    resp = client.post(
        "/api/v1/auth/dev",
        json={"name": "Focus Tester", "email": email},
    )
    assert resp.status_code == 200, resp.text
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_create_focus_session(client: TestClient) -> None:
    headers = _auth_headers(client)
    started = datetime.now(timezone.utc)
    resp = client.post(
        "/api/v1/focus/sessions",
        headers=headers,
        json={
            "task_id": None,
            "started_at": started.isoformat(),
            "ended_at": (started + timedelta(minutes=25)).isoformat(),
            "duration_seconds": 25 * 60,
            "category": "Work",
        },
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["user_id"]
    assert body["duration_seconds"] == 25 * 60
    assert body["category"] == "Work"
    assert uuid.UUID(body["id"])


def test_create_focus_session_blank_category_rejected(client: TestClient) -> None:
    headers = _auth_headers(client)
    started = datetime.now(timezone.utc)
    resp = client.post(
        "/api/v1/focus/sessions",
        headers=headers,
        json={
            "task_id": None,
            "started_at": started.isoformat(),
            "ended_at": (started + timedelta(minutes=25)).isoformat(),
            "duration_seconds": 25 * 60,
            "category": "   ",
        },
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["category"] is None


def test_end_before_start_rejected(client: TestClient) -> None:
    headers = _auth_headers(client)
    started = datetime.now(timezone.utc)
    resp = client.post(
        "/api/v1/focus/sessions",
        headers=headers,
        json={
            "task_id": None,
            "started_at": started.isoformat(),
            "ended_at": (started - timedelta(minutes=5)).isoformat(),
        },
    )
    assert resp.status_code == 422, resp.text


def test_list_and_summary(client: TestClient) -> None:
    headers = _auth_headers(client)
    now = datetime.now(timezone.utc)
    for minutes in (25, 45):
        client.post(
            "/api/v1/focus/sessions",
            headers=headers,
            json={
                "task_id": None,
                "started_at": now.isoformat(),
                "ended_at": (now + timedelta(minutes=minutes)).isoformat(),
                "duration_seconds": minutes * 60,
            },
        )

    listed = client.get("/api/v1/focus/sessions", headers=headers)
    assert listed.status_code == 200, listed.text
    assert len(listed.json()) == 2

    summary = client.get("/api/v1/focus/summary", headers=headers)
    assert summary.status_code == 200, summary.text
    body = summary.json()
    assert body["session_count"] == 2
    assert body["total_duration_seconds"] == 70 * 60
    assert body["analysis"]


def test_get_and_delete_focus_session(client: TestClient) -> None:
    headers = _auth_headers(client)
    now = datetime.now(timezone.utc)
    created = client.post(
        "/api/v1/focus/sessions",
        headers=headers,
        json={
            "task_id": None,
            "started_at": now.isoformat(),
            "ended_at": (now + timedelta(minutes=30)).isoformat(),
            "duration_seconds": 30 * 60,
        },
    ).json()
    session_id = created["id"]

    got = client.get(f"/api/v1/focus/sessions/{session_id}", headers=headers)
    assert got.status_code == 200, got.text
    assert got.json()["id"] == session_id

    deleted = client.delete(
        f"/api/v1/focus/sessions/{session_id}",
        headers=headers,
    )
    assert deleted.status_code == 200, deleted.text
    assert client.get(
        f"/api/v1/focus/sessions/{session_id}",
        headers=headers,
    ).status_code == 404


def test_update_focus_session_times(client: TestClient) -> None:
    headers = _auth_headers(client)
    now = datetime.now(timezone.utc)
    created = client.post(
        "/api/v1/focus/sessions",
        headers=headers,
        json={
            "task_id": None,
            "started_at": now.isoformat(),
            "ended_at": (now + timedelta(minutes=30)).isoformat(),
            "duration_seconds": 30 * 60,
        },
    ).json()
    session_id = created["id"]

    new_started = now - timedelta(minutes=10)
    new_ended = now + timedelta(minutes=40)
    resp = client.patch(
        f"/api/v1/focus/sessions/{session_id}",
        headers=headers,
        json={
            "started_at": new_started.isoformat(),
            "ended_at": new_ended.isoformat(),
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["id"] == session_id
    assert body["duration_seconds"] == 50 * 60


def test_update_focus_session_end_before_start_rejected(client: TestClient) -> None:
    headers = _auth_headers(client)
    now = datetime.now(timezone.utc)
    created = client.post(
        "/api/v1/focus/sessions",
        headers=headers,
        json={
            "task_id": None,
            "started_at": now.isoformat(),
            "ended_at": (now + timedelta(minutes=30)).isoformat(),
            "duration_seconds": 30 * 60,
        },
    ).json()

    resp = client.patch(
        f"/api/v1/focus/sessions/{created['id']}",
        headers=headers,
        json={
            "started_at": (now + timedelta(minutes=10)).isoformat(),
            "ended_at": now.isoformat(),
        },
    )
    assert resp.status_code == 422, resp.text


def test_update_focus_session_other_user_404(client: TestClient) -> None:
    creator = _auth_headers(client, email="updater@test.dev")
    now = datetime.now(timezone.utc)
    created = client.post(
        "/api/v1/focus/sessions",
        headers=creator,
        json={
            "task_id": None,
            "started_at": now.isoformat(),
            "ended_at": (now + timedelta(minutes=20)).isoformat(),
        },
    ).json()

    other = _auth_headers(client, email="updater-other@test.dev")
    resp = client.patch(
        f"/api/v1/focus/sessions/{created['id']}",
        headers=other,
        json={"started_at": now.isoformat()},
    )
    assert resp.status_code == 404, resp.text


def test_focus_session_other_user_404(client: TestClient) -> None:
    creator = _auth_headers(client, email="maker@test.dev")
    now = datetime.now(timezone.utc)
    created = client.post(
        "/api/v1/focus/sessions",
        headers=creator,
        json={
            "task_id": None,
            "started_at": now.isoformat(),
            "ended_at": (now + timedelta(minutes=20)).isoformat(),
        },
    ).json()

    other = _auth_headers(client, email="other@test.dev")
    resp = client.get(
        f"/api/v1/focus/sessions/{created['id']}",
        headers=other,
    )
    assert resp.status_code == 404, resp.text
