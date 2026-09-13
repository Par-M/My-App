import uuid
from datetime import date
from datetime import datetime
from datetime import timezone

from fastapi.testclient import TestClient


def _auth_headers(
    client: TestClient,
    *,
    email: str = "reflect@test.dev",
) -> dict[str, str]:
    resp = client.post(
        "/api/v1/auth/signup",
        json={"email": email, "password": "test-pass-123"},
    )
    assert resp.status_code == 201, resp.text
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _create(
    client: TestClient,
    headers: dict[str, str],
    *,
    text: str = "Today I stayed in flow on the backend focus feature.",
    on: date | None = None,
) -> dict:
    resp = client.post(
        "/api/v1/reflections",
        headers=headers,
        json={
            "date": (on or date.today()).isoformat(),
            "text": text,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_create_and_get_reflection(client: TestClient) -> None:
    headers = _auth_headers(client)
    created = _create(client, headers)
    reflection_id = created["id"]

    got = client.get(
        f"/api/v1/reflections/{reflection_id}",
        headers=headers,
    )
    assert got.status_code == 200, got.text
    assert got.json()["id"] == reflection_id
    assert uuid.UUID(reflection_id)


def test_create_daily_and_get(client: TestClient) -> None:
    headers = _auth_headers(client, email="daily@test.dev")
    resp = client.post(
        "/api/v1/reflections/daily",
        headers=headers,
        json={
            "date": date.today().isoformat(),
            "text": "Daily check-in: one thing that felt finished today.",
        },
    )
    assert resp.status_code == 201, resp.text
    reflection_id = resp.json()["id"]

    got = client.get(
        f"/api/v1/reflections/{reflection_id}",
        headers=headers,
    )
    assert got.status_code == 200, got.text
    assert got.json()["text"].startswith("Daily check-in")


def test_reflection_analysis(client: TestClient) -> None:
    headers = _auth_headers(client, email="analyze@test.dev")
    created = _create(client, headers)
    reflection_id = created["id"]

    analyzed = client.post(
        f"/api/v1/reflections/{reflection_id}/analysis",
        headers=headers,
    )
    assert analyzed.status_code == 200, analyzed.text
    assert "analysis" in analyzed.json()


def test_list_reflections(client: TestClient) -> None:
    headers = _auth_headers(client, email="listme@test.dev")
    for day_offset in range(3):
        d = date.fromisocalendar(2026, 1, 8 - day_offset * 20)
        _create(client, headers, on=d)

    listed = client.get("/api/v1/reflections", headers=headers)
    assert listed.status_code == 200, listed.text
    assert len(listed.json()) == 3


def test_delete_reflection(client: TestClient) -> None:
    headers = _auth_headers(client, email="delme@test.dev")
    created = _create(client, headers)
    reflection_id = created["id"]

    deleted = client.delete(
        f"/api/v1/reflections/{reflection_id}",
        headers=headers,
    )
    assert deleted.status_code == 200, deleted.text
    assert (
        client.get(
            f"/api/v1/reflections/{reflection_id}",
            headers=headers,
        ).status_code
        == 404
    )


def test_reflection_other_user_404(client: TestClient) -> None:
    owner = _auth_headers(client, email="owner@test.dev")
    created = _create(client, owner, text="Private reflection payload.")

    intruder = _auth_headers(client, email="intruder@test.dev")
    got = client.get(
        f"/api/v1/reflections/{created['id']}",
        headers=intruder,
    )
    assert got.status_code == 404, got.text
