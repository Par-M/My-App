import uuid
from datetime import datetime


def _parse(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


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
    payload = {"title": "Algorithms Assignment", "estimated_duration": 60}
    payload.update(overrides)
    response = client.post("/api/v1/tasks", json=payload, headers=_auth(token))
    assert response.status_code == 201
    return response.json()


def _generate(client, token, **overrides):
    payload = {
        "start_date": "2026-08-03",
        "end_date": "2026-08-09",
        "timezone": "UTC",
        "busy_times": [],
    }
    payload.update(overrides)
    return client.post(
        "/api/v1/schedule/generate", json=payload, headers=_auth(token)
    )


class TestGenerateSchedule:
    def test_requires_authentication(self, client):
        response = _generate(client, "invalid")
        assert response.status_code == 401

    def test_generates_proposal(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])

        response = _generate(client, data["access_token"])
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "pending"
        assert body["accepted"] is False
        assert body["reasoning"]
        assert body["items"]
        assert body["items"][0]["task_title"] == task["title"]
        assert body["meta"]["provider"] == "heuristic_fallback"
        assert body["meta"]["overcommitted"] is False
        assert body["meta"]["scheduleable_hours"] > 0
        assert body["message"]

    def test_respects_busy_times(self, client):
        data = _login(client)
        _create_task(client, data["access_token"])

        response = _generate(
            client,
            data["access_token"],
            busy_times=[
                {
                    "start": "2026-08-03T09:00:00+00:00",
                    "end": "2026-08-03T17:00:00+00:00",
                }
            ],
        )
        assert response.status_code == 200
        body = response.json()
        for item in body["items"]:
            assert item["start"] != "2026-08-03T09:00:00+00:00"

    def test_no_active_tasks_returns_empty_proposal(self, client):
        data = _login(client)
        response = _generate(client, data["access_token"])
        assert response.status_code == 200
        body = response.json()
        assert body["items"] == []
        assert "No active tasks" in body["message"]

    def test_rejects_end_before_start(self, client):
        data = _login(client)
        response = _generate(
            client,
            data["access_token"],
            start_date="2026-08-09",
            end_date="2026-08-03",
        )
        assert response.status_code == 422

    def test_rejects_invalid_timezone(self, client):
        data = _login(client)
        response = _generate(client, data["access_token"], timezone="Nope/Nowhere")
        assert response.status_code == 422

    def test_overcommitment_detected(self, client):
        data = _login(client)
        _create_task(client, data["access_token"], estimated_duration=600)

        response = _generate(
            client,
            data["access_token"],
            start_date="2026-08-03",
            end_date="2026-08-03",
        )
        assert response.status_code == 200
        body = response.json()
        assert body["meta"]["overcommitted"] is True
        assert body["meta"]["risk"]
        assert "Algorithms Assignment" in body["meta"]["deferred_tasks"]
        assert body["message"] and "deferred" in body["message"]


class TestAcceptRecommendation:
    def _proposal(self, client, token):
        response = _generate(client, token)
        assert response.status_code == 200
        return response.json()

    def test_accept_creates_calendar_blocks(self, client):
        data = _login(client)
        _create_task(client, data["access_token"])
        proposal = self._proposal(client, data["access_token"])

        response = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/accept",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["recommendation"]["status"] == "accepted"
        assert body["recommendation"]["accepted"] is True
        assert len(body["blocks"]) == 1
        block = body["blocks"][0]
        assert block["calendar_event_id"] is None

        listed = client.get(
            "/api/v1/calendar/blocks", headers=_auth(data["access_token"])
        ).json()
        assert listed["total"] == 1

    def test_long_task_is_chunked_into_multiple_blocks(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"], estimated_duration=300)
        proposal = self._proposal(client, data["access_token"])

        items = proposal["items"]
        assert len(items) == 4
        assert {item["task_id"] for item in items} == {task["id"]}
        total = sum(
            (_parse(item["end"]) - _parse(item["start"])).total_seconds() / 60
            for item in items
        )
        assert total == 300
        assert all(
            (_parse(item["end"]) - _parse(item["start"])).total_seconds() / 60
            <= 90
            for item in items
        )

        response = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/accept",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert len(response.json()["blocks"]) == 4

    def test_cannot_accept_twice(self, client):
        data = _login(client)
        _create_task(client, data["access_token"])
        proposal = self._proposal(client, data["access_token"])

        first = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/accept",
            headers=_auth(data["access_token"]),
        )
        assert first.status_code == 200

        second = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/accept",
            headers=_auth(data["access_token"]),
        )
        assert second.status_code == 409

    def test_unknown_recommendation_returns_404(self, client):
        data = _login(client)
        response = client.post(
            f"/api/v1/schedule/recommendations/{uuid.uuid4()}/accept",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404

    def test_user_cannot_accept_another_users_recommendation(self, client):
        owner = _login(client, "owner@example.com")
        _create_task(client, owner["access_token"])
        proposal = self._proposal(client, owner["access_token"])

        other = _login(client, "other@example.com")
        response = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/accept",
            headers=_auth(other["access_token"]),
        )
        assert response.status_code == 404

    def test_rejected_recommendation_cannot_be_accepted(self, client):
        data = _login(client)
        _create_task(client, data["access_token"])
        proposal = self._proposal(client, data["access_token"])

        rejected = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/reject",
            headers=_auth(data["access_token"]),
        )
        assert rejected.status_code == 200
        assert rejected.json()["status"] == "rejected"

        accepted = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/accept",
            headers=_auth(data["access_token"]),
        )
        assert accepted.status_code == 409


class TestListRecommendations:
    def test_lists_own_recommendations(self, client):
        data = _login(client)
        _create_task(client, data["access_token"])
        _generate(client, data["access_token"])

        response = client.get(
            "/api/v1/schedule/recommendations",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["status"] == "pending"

    def test_filters_by_status(self, client):
        data = _login(client)
        _create_task(client, data["access_token"])
        proposal = _generate(client, data["access_token"]).json()
        client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/reject",
            headers=_auth(data["access_token"]),
        )

        response = client.get(
            "/api/v1/schedule/recommendations?status=rejected",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 1

    def test_requires_authentication(self, client):
        assert (
            client.get("/api/v1/schedule/recommendations").status_code == 401
        )


class TestPreferences:
    def test_returns_defaults(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/preferences", headers=_auth(data["access_token"])
        )
        assert response.status_code == 200
        body = response.json()
        assert body["work_hours_start"] == 9
        assert body["work_hours_end"] == 17
        assert body["buffer_minutes"] == 15
        assert body["energy_level"] == 3
        assert body["max_daily_hours"] == 8
        assert body["default_duration_minutes"] == 30
        assert body["default_priority"] == "medium"

    def test_updates_preferences(self, client):
        data = _login(client)
        response = client.put(
            "/api/v1/preferences",
            json={
                "work_hours_start": 8,
                "work_hours_end": 18,
                "buffer_minutes": 30,
                "energy_level": 5,
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["work_hours_start"] == 8
        assert body["work_hours_end"] == 18
        assert body["buffer_minutes"] == 30
        assert body["energy_level"] == 5

    def test_updates_onboarding_preferences(self, client):
        data = _login(client)
        response = client.put(
            "/api/v1/preferences",
            json={
                "max_daily_hours": 6,
                "default_duration_minutes": 45,
                "default_priority": "high",
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["max_daily_hours"] == 6
        assert body["default_duration_minutes"] == 45
        assert body["default_priority"] == "high"

    def test_rejects_invalid_default_priority(self, client):
        data = _login(client)
        response = client.put(
            "/api/v1/preferences",
            json={"default_priority": "urgent"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422

    def test_partial_update(self, client):
        data = _login(client)
        response = client.put(
            "/api/v1/preferences",
            json={"buffer_minutes": 45},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["buffer_minutes"] == 45
        assert response.json()["energy_level"] == 3

    def test_rejects_invalid_energy_level(self, client):
        data = _login(client)
        response = client.put(
            "/api/v1/preferences",
            json={"energy_level": 9},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422

    def test_rejects_inverted_work_hours(self, client):
        data = _login(client)
        response = client.put(
            "/api/v1/preferences",
            json={"work_hours_start": 18, "work_hours_end": 8},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422

    def test_requires_authentication(self, client):
        assert client.get("/api/v1/preferences").status_code == 401
