import importlib
import uuid
from datetime import datetime
from datetime import timedelta
from datetime import timezone

import pytest

from app.models.task import TaskStatus


def _fake_now() -> datetime:
    real = datetime.now(timezone.utc)
    return real.replace(hour=9, minute=0, second=0, microsecond=0)


def _now() -> datetime:
    return _fake_now()


class _FakeDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        return _fake_now()


@pytest.fixture(autouse=True)
def _freeze_app_clock(monkeypatch):
    for module_name in (
        "app.services.planner_service",
        "app.services.task_service",
    ):
        monkeypatch.setattr(
            importlib.import_module(module_name), "datetime", _FakeDatetime
        )


def _login(client, email="planner@example.com", name="Planner"):
    response = client.post(
        "/api/v1/auth/dev",
        json={"name": name, "email": email},
    )
    assert response.status_code == 200
    return response.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _create_task(client, token, **overrides):
    payload = {"title": "Plan today"}
    payload.update(overrides)
    return client.post("/api/v1/tasks", json=payload, headers=_auth(token)).json()


def _create_block(client, token, task_id, start, end, **overrides):
    payload = {
        "task_id": task_id,
        "title": "Block",
        "start_at": start.isoformat(),
        "end_at": end.isoformat(),
    }
    payload.update(overrides)
    return client.post(
        "/api/v1/calendar/blocks", json=payload, headers=_auth(token)
    )


class TestStartComplete:
    def test_start_task_marks_in_progress(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])

        response = client.post(
            f"/api/v1/tasks/{task['id']}/start",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "in_progress"
        assert body["started_at"] is not None

    def test_start_preserves_existing_started_at(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        first = client.post(
            f"/api/v1/tasks/{task['id']}/start",
            headers=_auth(data["access_token"]),
        ).json()
        second = client.post(
            f"/api/v1/tasks/{task['id']}/start",
            headers=_auth(data["access_token"]),
        ).json()
        assert second["started_at"] == first["started_at"]

    def test_complete_task_records_minutes(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])

        response = client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={"actual_minutes": 45},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "completed"
        assert body["completed_at"] is not None
        assert body["actual_duration"] == 45

    def test_complete_is_idempotent(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={"actual_minutes": 30},
            headers=_auth(data["access_token"]),
        )
        response = client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={"actual_minutes": 15},
            headers=_auth(data["access_token"]),
        )
        assert response.json()["actual_duration"] == 30

    def test_start_completed_task_conflicts(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )
        response = client.post(
            f"/api/v1/tasks/{task['id']}/start",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 409

    def test_complete_unknown_task_returns_404(self, client):
        data = _login(client)
        response = client.post(
            f"/api/v1/tasks/{uuid.uuid4()}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404


class TestSnooze:
    def test_snooze_shifts_block_later_today(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        start = _now() + timedelta(hours=2)
        block = _create_block(
            client, data["access_token"], task["id"], start, start + timedelta(minutes=60)
        ).json()

        response = client.post(
            f"/api/v1/tasks/{task['id']}/snooze",
            json={"minutes": 30, "timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert len(body["blocks"]) == 1
        new_start = datetime.fromisoformat(
            body["blocks"][0]["start_at"].replace("Z", "+00:00")
        )
        assert new_start == start + timedelta(minutes=30)

    def test_snooze_without_block_leaves_unchanged(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])

        response = client.post(
            f"/api/v1/tasks/{task['id']}/snooze",
            json={"minutes": 30, "timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["blocks"] == []

    def test_snooze_completed_task_conflicts(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )
        response = client.post(
            f"/api/v1/tasks/{task['id']}/snooze",
            json={"minutes": 30},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 409

    def test_snooze_rejects_invalid_minutes(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        response = client.post(
            f"/api/v1/tasks/{task['id']}/snooze",
            json={"minutes": 0},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422


class TestToday:
    def test_empty_day(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/today?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["current_task"] is None
        assert body["next_tasks"] == []
        assert body["completed_today"] == 0
        assert body["focus_time_remaining"] >= 0
        assert 0 <= body["day_progress"] <= 1

    def test_current_task_from_running_block(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"], title="Running now")
        _create_block(
            client,
            data["access_token"],
            task["id"],
            _now() - timedelta(minutes=30),
            _now() + timedelta(minutes=30),
        )

        response = client.get(
            "/api/v1/today?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert body["current_task"]["id"] == task["id"]
        assert body["current_task"]["title"] == "Running now"

    def test_next_tasks_ordered_by_start(self, client):
        data = _login(client)
        later = _create_task(client, data["access_token"], title="Later task")
        sooner = _create_task(client, data["access_token"], title="Sooner task")
        _create_block(
            client,
            data["access_token"],
            sooner["id"],
            _now() + timedelta(hours=1),
            _now() + timedelta(hours=2),
        )
        _create_block(
            client,
            data["access_token"],
            later["id"],
            _now() + timedelta(hours=3),
            _now() + timedelta(hours=4),
        )

        response = client.get(
            "/api/v1/today?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        titles = [task["title"] for task in body["next_tasks"]]
        assert titles == ["Sooner task", "Later task"]

    def test_priority_task_is_highest_priority_scheduled(self, client):
        data = _login(client)
        low = _create_task(client, data["access_token"], title="Low", priority="low")
        high = _create_task(client, data["access_token"], title="High", priority="high")
        _create_block(
            client,
            data["access_token"],
            low["id"],
            _now() + timedelta(hours=1),
            _now() + timedelta(hours=2),
        )
        _create_block(
            client,
            data["access_token"],
            high["id"],
            _now() + timedelta(hours=3),
            _now() + timedelta(hours=4),
        )

        response = client.get(
            "/api/v1/today?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["priority_task"]["title"] == "High"

    def test_completed_today_count(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )

        response = client.get(
            "/api/v1/today?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["completed_today"] == 1

    def test_requires_authentication(self, client):
        response = client.get("/api/v1/today")
        assert response.status_code == 401

    def test_rejects_invalid_timezone(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/today?timezone=Not/AZone",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422


class TestDailySummary:
    def test_empty_day(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/daily-summary?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["completed"] == []
        assert body["in_progress"] == []
        assert body["pending"] == []
        assert body["hours_worked"] == 0
        assert body["tasks_remaining"] == 0
        assert body["tasks_moved"] == 0
        assert body["schedule_adherence"] == 1.0

    def test_counts_completed_and_hours(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"], title="Deep work")
        client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={"actual_minutes": 120},
            headers=_auth(data["access_token"]),
        )

        response = client.get(
            "/api/v1/daily-summary?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert [t["title"] for t in body["completed"]] == ["Deep work"]
        assert body["hours_worked"] == 2.0
        assert body["tasks_remaining"] == 0

    def test_adherence_counts_planned(self, client):
        data = _login(client)
        done = _create_task(client, data["access_token"], title="Done")
        open_task = _create_task(client, data["access_token"], title="Open")
        _create_block(
            client,
            data["access_token"],
            done["id"],
            _now() + timedelta(hours=1),
            _now() + timedelta(hours=2),
        )
        _create_block(
            client,
            data["access_token"],
            open_task["id"],
            _now() + timedelta(hours=3),
            _now() + timedelta(hours=4),
        )
        client.post(
            f"/api/v1/tasks/{done['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )

        response = client.get(
            "/api/v1/daily-summary?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert body["schedule_adherence"] == 0.5
        assert body["tasks_remaining"] == 1
        assert [t["title"] for t in body["pending"]] == ["Open"]

    def test_counts_moved_tasks(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        block = _create_block(
            client,
            data["access_token"],
            task["id"],
            _now() + timedelta(hours=1),
            _now() + timedelta(hours=2),
        ).json()
        client.patch(
            f"/api/v1/calendar/blocks/{block['id']}",
            json={
                "start_at": (_now() + timedelta(hours=5)).isoformat(),
                "end_at": (_now() + timedelta(hours=6)).isoformat(),
            },
            headers=_auth(data["access_token"]),
        )

        response = client.get(
            "/api/v1/daily-summary?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["tasks_moved"] == 1

    def test_requires_authentication(self, client):
        response = client.get("/api/v1/daily-summary")
        assert response.status_code == 401


class TestOverdue:
    def test_lists_overdue_tasks_only(self, client):
        data = _login(client)
        late = _create_task(
            client,
            data["access_token"],
            title="Late task",
            deadline=(_now() - timedelta(days=1)).isoformat(),
        )
        on_time = _create_task(
            client,
            data["access_token"],
            title="On time",
            deadline=(_now() + timedelta(days=1)).isoformat(),
        )
        done = _create_task(
            client,
            data["access_token"],
            title="Done late",
            deadline=(_now() - timedelta(days=1)).isoformat(),
        )
        client.post(
            f"/api/v1/tasks/{done['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )

        response = client.get(
            "/api/v1/tasks/overdue", headers=_auth(data["access_token"])
        )
        assert response.status_code == 200
        titles = [task["title"] for task in response.json()["items"]]
        assert titles == ["Late task"]
        assert on_time["id"] not in titles

    def test_excludes_tasks_without_deadline(self, client):
        data = _login(client)
        _create_task(client, data["access_token"], title="No deadline")

        response = client.get(
            "/api/v1/tasks/overdue", headers=_auth(data["access_token"])
        )
        assert response.json()["total"] == 0

    def test_requires_authentication(self, client):
        assert client.get("/api/v1/tasks/overdue").status_code == 401


class TestReschedule:
    def test_reschedule_updates_deadline_and_shifts_blocks(self, client):
        data = _login(client)
        task = _create_task(
            client,
            data["access_token"],
            title="Missed task",
            category="Work",
            deadline=(_now() - timedelta(hours=3)).isoformat(),
        )
        start = _now() - timedelta(hours=2)
        _create_block(
            client,
            data["access_token"],
            task["id"],
            start,
            start + timedelta(minutes=60),
        )

        response = client.post(
            f"/api/v1/tasks/{task['id']}/reschedule",
            json={
                "minutes_remaining": 90,
                "reason": "Got pulled into a meeting",
                "timezone": "UTC",
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        new_deadline = datetime.fromisoformat(
            body["task"]["deadline"].replace("Z", "+00:00")
        )
        assert new_deadline == _now() + timedelta(minutes=90)
        assert body["task"]["estimated_duration"] == 90

        assert len(body["blocks"]) == 1
        block_start = datetime.fromisoformat(
            body["blocks"][0]["start_at"].replace("Z", "+00:00")
        )
        block_end = datetime.fromisoformat(
            body["blocks"][0]["end_at"].replace("Z", "+00:00")
        )
        assert block_start == _now()
        assert block_end == _now() + timedelta(minutes=60)

    def test_reschedule_keeps_completed_blocks_in_place(self, client):
        data = _login(client)
        task = _create_task(
            client,
            data["access_token"],
            deadline=(_now() - timedelta(hours=3)).isoformat(),
        )
        done_start = _now() - timedelta(hours=3)
        remaining_start = _now() - timedelta(hours=2)
        done_block = _create_block(
            client,
            data["access_token"],
            task["id"],
            done_start,
            done_start + timedelta(minutes=60),
        ).json()
        _create_block(
            client,
            data["access_token"],
            task["id"],
            remaining_start,
            remaining_start + timedelta(minutes=60),
        )
        client.post(
            f"/api/v1/calendar/blocks/{done_block['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )

        response = client.post(
            f"/api/v1/tasks/{task['id']}/reschedule",
            json={"minutes_remaining": 60, "timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        moved = [
            datetime.fromisoformat(block["start_at"].replace("Z", "+00:00"))
            for block in body["blocks"]
            if block["id"] != done_block["id"]
        ]
        assert moved == [_now() + timedelta(minutes=0)]

    def test_reschedule_without_deadline_conflicts(self, client):
        data = _login(client)
        task = _create_task(client, data["access_token"])
        response = client.post(
            f"/api/v1/tasks/{task['id']}/reschedule",
            json={"minutes_remaining": 30, "timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 409

    def test_reschedule_completed_task_conflicts(self, client):
        data = _login(client)
        task = _create_task(
            client,
            data["access_token"],
            deadline=(_now() - timedelta(days=1)).isoformat(),
        )
        client.post(
            f"/api/v1/tasks/{task['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )
        response = client.post(
            f"/api/v1/tasks/{task['id']}/reschedule",
            json={"minutes_remaining": 30, "timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 409

    def test_reschedule_rejects_invalid_minutes(self, client):
        data = _login(client)
        task = _create_task(
            client,
            data["access_token"],
            deadline=(_now() - timedelta(days=1)).isoformat(),
        )
        response = client.post(
            f"/api/v1/tasks/{task['id']}/reschedule",
            json={"minutes_remaining": 0},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422


class TestMissedReasons:
    def _reschedule(self, client, token, title, category):
        task = _create_task(
            client,
            token,
            title=title,
            category=category,
            deadline=(_now() - timedelta(days=1)).isoformat(),
        )
        client.post(
            f"/api/v1/tasks/{task['id']}/reschedule",
            json={
                "minutes_remaining": 45,
                "reason": "Reason for " + title,
                "timezone": "UTC",
            },
            headers=_auth(token),
        )
        return task

    def test_daily_summary_includes_missed_today(self, client):
        data = _login(client)
        self._reschedule(client, data["access_token"], "Late", "Work")

        response = client.get(
            "/api/v1/daily-summary?timezone=UTC",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert len(body["missed_today"]) == 1
        entry = body["missed_today"][0]
        assert entry["task_title"] == "Late"
        assert entry["category"] == "Work"
        assert entry["reason"] == "Reason for Late"
        assert entry["minutes_remaining"] == 45

    def test_missed_reasons_groups_by_category(self, client):
        data = _login(client)
        work_one = self._reschedule(
            client, data["access_token"], "Late one", "Work"
        )
        self._reschedule(client, data["access_token"], "Late two", "Work")
        self._reschedule(
            client, data["access_token"], "Home late", "Home"
        )

        response = client.get(
            "/api/v1/missed-reasons",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 3
        assert [group["category"] for group in body["by_category"]] == [
            "Work",
            "Home",
        ]
        work_group = body["by_category"][0]
        assert work_group["count"] == 2
        assert sorted(
            entry["task_title"] for entry in work_group["reasons"]
        ) == ["Late one", "Late two"]

    def test_missed_reasons_empty(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/missed-reasons",
            headers=_auth(data["access_token"]),
        )
        assert response.json() == {"total": 0, "by_category": []}

    def test_requires_authentication(self, client):
        assert client.get("/api/v1/missed-reasons").status_code == 401
