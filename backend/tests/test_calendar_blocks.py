import uuid
from datetime import datetime
from datetime import timedelta
from datetime import timezone

NOW = datetime.now(timezone.utc)


def _login(client, email="parthiv@example.com", name="Parthiv"):
    response = client.post(
        "/api/v1/auth/dev",
        json={"name": name, "email": email},
    )
    assert response.status_code == 200
    return response.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _create_task(client, token, **overrides):
    payload = {"title": "Study Algorithms", "estimated_duration": 60}
    payload.update(overrides)
    response = client.post("/api/v1/tasks", json=payload, headers=_auth(token))
    assert response.status_code == 201
    return response.json()


def _block_payload(task_id, **overrides):
    payload = {
        "task_id": task_id,
        "title": "Study Algorithms",
        "start_at": (NOW + timedelta(hours=2)).isoformat(),
        "end_at": (NOW + timedelta(hours=4)).isoformat(),
        "calendar_event_id": "event-abc-123",
    }
    payload.update(overrides)
    return payload


class TestCalendarBlockAuth:
    def test_requires_authentication(self, client):
        assert client.get("/api/v1/calendar/blocks").status_code == 401
        assert client.post("/api/v1/calendar/blocks", json={}).status_code == 401
        assert client.patch(
            f"/api/v1/calendar/blocks/{uuid.uuid4()}", json={}
        ).status_code == 401
        assert client.delete(
            f"/api/v1/calendar/blocks/{uuid.uuid4()}"
        ).status_code == 401


class TestCreateCalendarBlock:
    def test_creates_block(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])

        response = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(task["id"]),
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 201
        body = response.json()
        assert body["title"] == "Study Algorithms"
        assert body["task_id"] == task["id"]
        assert body["calendar_event_id"] == "event-abc-123"
        assert body["created_at"]

    def test_requires_existing_own_task(self, client):
        data = _login(client)
        response = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(str(uuid.uuid4())),
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404

    def test_rejects_other_users_task(self, client):
        owner = _login(client, "owner@example.com")
        task = _create_task(client, owner["access_token"])

        other = _login(client, "other@example.com")
        response = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(task["id"]),
            headers=_auth(other["access_token"]),
        )
        assert response.status_code == 404

    def test_rejects_end_before_start(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        response = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(
                task["id"],
                start_at=(NOW + timedelta(hours=4)).isoformat(),
                end_at=(NOW + timedelta(hours=2)).isoformat(),
            ),
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422


class TestCalendarBlockLifecycle:
    def test_list_update_delete(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        created = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(task["id"]),
            headers=_auth(data["access_token"]),
        ).json()

        listed = client.get(
            "/api/v1/calendar/blocks", headers=_auth(data["access_token"])
        ).json()
        assert listed["total"] == 1
        assert listed["items"][0]["id"] == created["id"]

        new_start = NOW + timedelta(hours=5)
        new_end = NOW + timedelta(hours=6)
        updated = client.patch(
            f"/api/v1/calendar/blocks/{created['id']}",
            json={"start_at": new_start.isoformat(), "end_at": new_end.isoformat()},
            headers=_auth(data["access_token"]),
        )
        assert updated.status_code == 200
        assert (
            datetime.fromisoformat(
                updated.json()["start_at"].replace("Z", "+00:00")
            ).timestamp()
            == new_start.timestamp()
        )

        deleted = client.delete(
            f"/api/v1/calendar/blocks/{created['id']}",
            headers=_auth(data["access_token"]),
        )
        assert deleted.status_code == 200

        listed = client.get(
            "/api/v1/calendar/blocks", headers=_auth(data["access_token"])
        ).json()
        assert listed["total"] == 0

    def test_user_cannot_update_another_users_block(self, client):
        owner = _login(client, "owner@example.com")
        task = _create_task(client, owner["access_token"])
        created = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(task["id"]),
            headers=_auth(owner["access_token"]),
        ).json()

        other = _login(client, "other@example.com")
        response = client.patch(
            f"/api/v1/calendar/blocks/{created['id']}",
            json={"title": "Hijacked"},
            headers=_auth(other["access_token"]),
        )
        assert response.status_code == 404

    def test_update_unknown_block_returns_404(self, client):
        data = _login(client)
        response = client.patch(
            f"/api/v1/calendar/blocks/{uuid.uuid4()}",
            json={"title": "x"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404

    def test_delete_unknown_block_returns_404(self, client):
        data = _login(client)
        response = client.delete(
            f"/api/v1/calendar/blocks/{uuid.uuid4()}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404


class TestCalendarBlockSync:
    def test_filters_by_since(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        created = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(task["id"]),
            headers=_auth(data["access_token"]),
        ).json()
        created_at = created["updated_at"]

        response = client.get(
            f"/api/v1/calendar/blocks?since={created_at}",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["id"] == created["id"]

        later = datetime.fromisoformat(
            created_at.replace("Z", "+00:00")
        ) + timedelta(days=1)
        response = client.get(
            f"/api/v1/calendar/blocks?since={later.isoformat().replace('+00:00', 'Z')}",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 0


class TestBlockCompletion:
    def _blocks(self, client, token, task_id):
        first = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(task_id),
            headers=_auth(token),
        ).json()
        second = client.post(
            "/api/v1/calendar/blocks",
            json=_block_payload(
                task_id,
                title="Study Algorithms",
                start_at=(NOW + timedelta(hours=5)).isoformat(),
                end_at=(NOW + timedelta(hours=6)).isoformat(),
            ),
            headers=_auth(token),
        ).json()
        return first, second

    def test_complete_block_records_note_and_progress(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        first, _ = self._blocks(client, data["access_token"], task["id"])

        response = client.post(
            f"/api/v1/calendar/blocks/{first['id']}/complete",
            json={"note": "Finished the first half"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["completed_at"]
        assert body["completion_note"] == "Finished the first half"

        task_after = client.get(
            f"/api/v1/tasks/{task['id']}", headers=_auth(data["access_token"])
        ).json()
        assert task_after["progress_percent"] == 50

    def test_complete_all_blocks_sets_100_percent(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        first, second = self._blocks(client, data["access_token"], task["id"])
        headers = _auth(data["access_token"])
        client.post(
            f"/api/v1/calendar/blocks/{first['id']}/complete",
            json={},
            headers=headers,
        )
        client.post(
            f"/api/v1/calendar/blocks/{second['id']}/complete",
            json={},
            headers=headers,
        )
        task_after = client.get(
            f"/api/v1/tasks/{task['id']}", headers=headers
        ).json()
        assert task_after["progress_percent"] == 100

    def test_reopen_block_clears_completion(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        first, _ = self._blocks(client, data["access_token"], task["id"])
        headers = _auth(data["access_token"])
        client.post(
            f"/api/v1/calendar/blocks/{first['id']}/complete",
            json={"note": "Done"},
            headers=headers,
        )
        reopened = client.post(
            f"/api/v1/calendar/blocks/{first['id']}/reopen",
            headers=headers,
        )
        assert reopened.status_code == 200
        assert reopened.json()["completed_at"] is None
        assert reopened.json()["completion_note"] is None

        task_after = client.get(
            f"/api/v1/tasks/{task['id']}", headers=headers
        ).json()
        assert task_after["progress_percent"] == 0

    def test_delete_uncompleted_block_raises_progress(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        first, second = self._blocks(client, data["access_token"], task["id"])
        headers = _auth(data["access_token"])
        client.post(
            f"/api/v1/calendar/blocks/{first['id']}/complete",
            json={},
            headers=headers,
        )
        client.delete(
            f"/api/v1/calendar/blocks/{second['id']}", headers=headers
        )
        task_after = client.get(
            f"/api/v1/tasks/{task['id']}", headers=headers
        ).json()
        assert task_after["progress_percent"] == 100

    def test_complete_unknown_block_returns_404(self, client):
        data = _login(client)
        response = client.post(
            f"/api/v1/calendar/blocks/{uuid.uuid4()}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404

    def test_requires_authentication(self, client):
        assert client.post(
            f"/api/v1/calendar/blocks/{uuid.uuid4()}/complete", json={}
        ).status_code == 401
        assert client.post(
            f"/api/v1/calendar/blocks/{uuid.uuid4()}/reopen"
        ).status_code == 401
