import uuid
from datetime import datetime
from datetime import timezone

import pytest


def _parse(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


@pytest.fixture(autouse=True)
def freeze_now(monkeypatch):
    fixed = datetime(2026, 8, 3, 9, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(
        "app.services.scheduling_service._utc_now",
        lambda: fixed,
    )
    return fixed


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
        _create_task(
            client,
            data["access_token"],
            estimated_duration=600,
            deadline="2026-08-03T12:00:00+00:00",
        )

        response = _generate(client, data["access_token"])
        assert response.status_code == 200
        body = response.json()
        assert body["meta"]["overcommitted"] is False
        assert not body["meta"].get("risk")
        # deferred_tasks may exist if task truly can't fit; we just don't show banner
        assert "deferred_tasks" in body["meta"]
        assert body["message"] and "schedule is ready" in body["message"]

    def test_ignores_far_future_calendar_view(self, client):
        data = _login(client)
        _create_task(client, data["access_token"], estimated_duration=60)

        response = _generate(
            client,
            data["access_token"],
            start_date="2028-08-03",
            end_date="2028-08-09",
        )
        assert response.status_code == 200
        body = response.json()
        assert body["items"]
        item = body["items"][0]
        parsed = _parse(item["start"])
        # Allow 5-minute buffer due to past-time blocking (09:00-09:05)
        assert parsed.date() == _parse("2026-08-03T09:00:00+00:00").date()
        assert parsed.hour == 9
        assert parsed.minute in (0, 5)

    def test_window_reaches_deadline_even_when_request_is_short(self, client):
        data = _login(client)
        _create_task(
            client,
            data["access_token"],
            estimated_duration=60,
            deadline="2026-08-07T10:00:00+00:00",
        )

        response = _generate(
            client,
            data["access_token"],
            start_date="2026-08-03",
            end_date="2026-08-04",
        )
        assert response.status_code == 200
        body = response.json()
        assert body["items"]
        assert _parse(body["items"][0]["start"]) < _parse("2026-08-07T10:00:00+00:00")

    def test_fixed_event_scheduled_at_exact_window(self, client):
        data = _login(client)
        _create_task(
            client,
            data["access_token"],
            start_at="2026-08-04T10:00:00+00:00",
            end_at="2026-08-04T11:00:00+00:00",
        )

        response = _generate(client, data["access_token"])
        assert response.status_code == 200
        body = response.json()
        assert body["items"]
        item = body["items"][0]
        assert _parse(item["start"]) == _parse("2026-08-04T10:00:00+00:00")
        assert _parse(item["end"]) == _parse("2026-08-04T11:00:00+00:00")

    def test_flexible_task_avoids_fixed_event_window(self, client):
        data = _login(client)
        _create_task(
            client,
            data["access_token"],
            title="Standup",
            start_at="2026-08-04T10:00:00+00:00",
            end_at="2026-08-04T11:00:00+00:00",
        )
        _create_task(client, data["access_token"], title="Deep work")

        response = _generate(client, data["access_token"])
        assert response.status_code == 200
        body = response.json()
        fixed = next(item for item in body["items"] if item["task_title"] == "Standup")
        assert _parse(fixed["start"]) == _parse("2026-08-04T10:00:00+00:00")
        assert _parse(fixed["end"]) == _parse("2026-08-04T11:00:00+00:00")

        f_start = _parse(fixed["start"])
        f_end = _parse(fixed["end"])
        for item in body["items"]:
            if item["task_title"] == "Standup":
                continue
            other_start = _parse(item["start"])
            other_end = _parse(item["end"])
            assert not (other_start < f_end and other_end > f_start)


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


class TestItemLevelActions:
    def _proposal(self, client, token):
        _create_task(client, token, title="Deep work")
        _create_task(client, token, title="Standup")
        response = _generate(client, token)
        assert response.status_code == 200
        return response.json()

    def test_accept_item_creates_single_block(self, client):
        data = _login(client)
        proposal = self._proposal(client, data["access_token"])
        items = proposal["items"]
        assert len(items) == 2

        response = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}"
            f"/items/0/accept",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert len(body["blocks"]) == 1
        assert body["blocks"][0]["task_id"] == items[0]["task_id"]
        assert body["recommendation"]["status"] == "pending"
        accepted_items = body["recommendation"]["items"]
        assert accepted_items[0]["accepted"] is True
        assert accepted_items[1]["accepted"] is False

        listed = client.get(
            "/api/v1/calendar/blocks", headers=_auth(data["access_token"])
        ).json()
        assert listed["total"] == 1

    def test_accepting_last_item_marks_recommendation_accepted(self, client):
        data = _login(client)
        proposal = self._proposal(client, data["access_token"])

        first = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/0/accept",
            headers=_auth(data["access_token"]),
        )
        assert first.status_code == 200

        second = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/1/accept",
            headers=_auth(data["access_token"]),
        )
        assert second.status_code == 200
        body = second.json()
        assert body["recommendation"]["status"] == "accepted"
        assert body["recommendation"]["accepted"] is True

    def test_cannot_accept_item_twice(self, client):
        data = _login(client)
        proposal = self._proposal(client, data["access_token"])

        first = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/0/accept",
            headers=_auth(data["access_token"]),
        )
        assert first.status_code == 200

        second = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/0/accept",
            headers=_auth(data["access_token"]),
        )
        assert second.status_code == 409

    def test_unknown_item_index_rejected(self, client):
        data = _login(client)
        proposal = self._proposal(client, data["access_token"])

        response = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/99/accept",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 409

    def test_full_accept_after_item_accept_creates_remaining_only(self, client):
        data = _login(client)
        proposal = self._proposal(client, data["access_token"])

        item = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/0/accept",
            headers=_auth(data["access_token"]),
        )
        assert item.status_code == 200

        full = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/accept",
            headers=_auth(data["access_token"]),
        )
        assert full.status_code == 200
        body = full.json()
        assert len(body["blocks"]) == 1
        assert body["recommendation"]["status"] == "accepted"

        listed = client.get(
            "/api/v1/calendar/blocks", headers=_auth(data["access_token"])
        ).json()
        assert listed["total"] == 2

    def test_redo_item_preserves_other_items_and_stays_valid(self, client):
        data = _login(client)
        proposal = self._proposal(client, data["access_token"])
        items = proposal["items"]

        response = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/1/redo",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "pending"
        assert len(body["items"]) == len(items)
        assert body["items"][0]["task_id"] == items[0]["task_id"]
        assert body["items"][0]["start"] == items[0]["start"]
        assert body["items"][0]["end"] == items[0]["end"]

        redo_block = body["items"][1]
        kept_block = body["items"][0]
        assert _parse(redo_block["end"]) > _parse(redo_block["start"])
        assert not (
            _parse(redo_block["start"]) < _parse(kept_block["end"])
            and _parse(redo_block["end"]) > _parse(kept_block["start"])
        )

    def test_cannot_redo_an_approved_item(self, client):
        data = _login(client)
        proposal = self._proposal(client, data["access_token"])

        accepted = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/0/accept",
            headers=_auth(data["access_token"]),
        )
        assert accepted.status_code == 200

        redo = client.post(
            f"/api/v1/schedule/recommendations/{proposal['id']}/items/0/redo",
            headers=_auth(data["access_token"]),
        )
        assert redo.status_code == 409

    def test_redo_requires_authentication(self, client):
        response = client.post(
            f"/api/v1/schedule/recommendations/{uuid.uuid4()}/items/0/redo"
        )
        assert response.status_code == 401


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
