import uuid
from datetime import date
from datetime import datetime
from datetime import time as dt_time
from datetime import timedelta
from datetime import timezone

from sqlalchemy import text

from app.db.database import engine


def _login(client, email="habits@example.com", name="Habits"):
    response = client.post(
        "/api/v1/auth/dev",
        json={"name": name, "email": email},
    )
    assert response.status_code == 200
    return response.json()


def _utc_today() -> date:
    return datetime.now(timezone.utc).date()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _create_habit(client, token, **overrides):
    payload = {"title": "Read"}
    payload.update(overrides)
    return client.post(
        "/api/v1/habits", json=payload, headers=_auth(token)
    ).json()


def _log(client, token, habit_id, **overrides):
    payload = {}
    payload.update(overrides)
    return client.post(
        f"/api/v1/habits/{habit_id}/logs",
        json=payload,
        headers=_auth(token),
    )


def _backdate_habit(habit_id, days_ago):
    created = datetime.combine(
        _utc_today() - timedelta(days=days_ago),
        dt_time.min,
        tzinfo=timezone.utc,
    )
    with engine.begin() as conn:
        conn.execute(
            text("UPDATE habits SET created_at = :ts WHERE id = :id"),
            {"ts": created.isoformat(), "id": str(habit_id)},
        )


def _app_weekday(today: date) -> int:
    return (today.weekday() + 1) % 7


class TestHabitAuth:
    def test_list_requires_authentication(self, client):
        assert client.get("/api/v1/habits").status_code == 401

    def test_dashboard_requires_authentication(self, client):
        assert client.get("/api/v1/habits/dashboard").status_code == 401

    def test_create_requires_authentication(self, client):
        response = client.post("/api/v1/habits", json={"title": "Read"})
        assert response.status_code == 401

    def test_update_requires_authentication(self, client):
        response = client.patch(
            f"/api/v1/habits/{uuid.uuid4()}", json={"title": "New"}
        )
        assert response.status_code == 401

    def test_delete_requires_authentication(self, client):
        response = client.delete(f"/api/v1/habits/{uuid.uuid4()}")
        assert response.status_code == 401

    def test_log_requires_authentication(self, client):
        response = client.post(
            f"/api/v1/habits/{uuid.uuid4()}/logs", json={"count": 1}
        )
        assert response.status_code == 401


class TestCreateHabit:
    def test_creates_habit_with_defaults(self, client):
        data = _login(client)
        body = _create_habit(client, data["access_token"], title="Read")

        assert body["title"] == "Read"
        assert body["repeat_weekdays"] is None
        assert body["daily_goal"] == 1
        assert body["user_id"] is not None

    def test_creates_with_weekdays_and_goal(self, client):
        data = _login(client)
        body = _create_habit(
            client,
            data["access_token"],
            title="Workout",
            repeat_weekdays=[3, 0, 6, 3],
            daily_goal=2,
        )

        assert body["repeat_weekdays"] == [0, 3, 6]
        assert body["daily_goal"] == 2

    def test_rejects_blank_title(self, client):
        data = _login(client)
        response = client.post(
            "/api/v1/habits",
            json={"title": "   "},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422

    def test_rejects_invalid_weekday(self, client):
        data = _login(client)
        response = client.post(
            "/api/v1/habits",
            json={"title": "Read", "repeat_weekdays": [9]},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422


class TestListHabits:
    def test_lists_habits(self, client):
        data = _login(client)
        _create_habit(client, data["access_token"], title="Read")
        _create_habit(client, data["access_token"], title="Run")

        response = client.get(
            "/api/v1/habits", headers=_auth(data["access_token"])
        )
        assert response.status_code == 200
        body = response.json()
        assert body["total"] == 2
        assert {h["title"] for h in body["items"]} == {"Read", "Run"}


class TestUpdateHabit:
    def test_updates_habit(self, client):
        data = _login(client)
        habit = _create_habit(client, data["access_token"], title="Read")
        habit_id = habit["id"]

        response = client.patch(
            f"/api/v1/habits/{habit_id}",
            json={"title": "Read 30m", "daily_goal": 3},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["title"] == "Read 30m"
        assert body["daily_goal"] == 3

    def test_update_clears_weekdays(self, client):
        data = _login(client)
        habit = _create_habit(
            client,
            data["access_token"],
            title="Read",
            repeat_weekdays=[1, 2],
        )

        response = client.patch(
            f"/api/v1/habits/{habit['id']}",
            json={"repeat_weekdays": None},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["repeat_weekdays"] is None

    def test_update_unknown_habit_returns_404(self, client):
        data = _login(client)
        response = client.patch(
            f"/api/v1/habits/{uuid.uuid4()}",
            json={"title": "New"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404


class TestDeleteHabit:
    def test_deletes_habit(self, client):
        data = _login(client)
        habit = _create_habit(client, data["access_token"], title="Read")

        response = client.delete(
            f"/api/v1/habits/{habit['id']}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200

        listing = client.get(
            "/api/v1/habits", headers=_auth(data["access_token"])
        ).json()
        assert listing["total"] == 0

    def test_delete_unknown_habit_returns_404(self, client):
        data = _login(client)
        response = client.delete(
            f"/api/v1/habits/{uuid.uuid4()}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404


class TestLogCompletion:
    def test_logs_completion(self, client):
        data = _login(client)
        habit = _create_habit(client, data["access_token"], title="Read")

        response = _log(
            client,
            data["access_token"],
            habit["id"],
            count=3,
            date=_utc_today().isoformat(),
        )
        assert response.status_code == 201
        body = response.json()
        assert body["habit_id"] == habit["id"]
        assert body["count"] == 3

    def test_log_unknown_habit_returns_404(self, client):
        data = _login(client)
        response = _log(client, data["access_token"], str(uuid.uuid4()))
        assert response.status_code == 404

    def test_rejects_zero_count(self, client):
        data = _login(client)
        habit = _create_habit(client, data["access_token"])
        response = _log(client, data["access_token"], habit["id"], count=0)
        assert response.status_code == 422


class TestDashboard:
    def test_empty_dashboard(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/habits/dashboard",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["habits"] == []

    def test_created_today_logged_today(self, client):
        data = _login(client)
        habit = _create_habit(client, data["access_token"], title="Read")
        today = _utc_today()
        _log(
            client,
            data["access_token"],
            habit["id"],
            count=2,
            date=today.isoformat(),
        )

        response = client.get(
            "/api/v1/habits/dashboard",
            headers=_auth(data["access_token"]),
        )
        stats = response.json()["habits"][0]
        assert stats["habit"]["title"] == "Read"
        assert stats["current_streak"] == 1
        assert stats["best_streak"] == 1
        assert stats["total_completions"] == 2
        assert stats["scheduled_7d"] == 1
        assert stats["completed_7d"] == 1
        assert stats["completion_rate_7d"] == 1.0
        assert stats["last_7_days"][-1]["completed_count"] == 2
        assert stats["last_7_days"][-1]["scheduled"] is True

    def test_streak_spans_backdated_days(self, client):
        data = _login(client)
        habit = _create_habit(client, data["access_token"], title="Meditate")
        _backdate_habit(habit["id"], days_ago=9)
        today = _utc_today()
        for offset in range(6):
            _log(
                client,
                data["access_token"],
                habit["id"],
                date=(today - timedelta(days=offset)).isoformat(),
            )

        stats = client.get(
            "/api/v1/habits/dashboard",
            headers=_auth(data["access_token"]),
        ).json()["habits"][0]
        assert stats["current_streak"] == 6
        assert stats["best_streak"] == 6
        assert stats["total_completions"] == 6
        assert stats["scheduled_7d"] == 7
        assert stats["completed_7d"] == 6
        assert stats["completion_rate_7d"] == 0.86

    def test_rate_reflects_missed_days(self, client):
        data = _login(client)
        habit = _create_habit(client, data["access_token"], title="Walk")
        _backdate_habit(habit["id"], days_ago=9)
        today = _utc_today()
        for offset in range(7):
            if offset in (2, 5):
                continue
            _log(
                client,
                data["access_token"],
                habit["id"],
                date=(today - timedelta(days=offset)).isoformat(),
            )

        stats = client.get(
            "/api/v1/habits/dashboard",
            headers=_auth(data["access_token"]),
        ).json()["habits"][0]
        assert stats["scheduled_7d"] == 7
        assert stats["completed_7d"] == 5
        assert stats["completion_rate_7d"] == 0.71
        assert stats["current_streak"] == 2
        assert stats["best_streak"] == 2

    def test_weekday_habit_counts_only_scheduled_days(self, client):
        data = _login(client)
        today = _utc_today()
        scheduled_today = _app_weekday(today)
        not_scheduled = (scheduled_today + 1) % 7

        on = _create_habit(
            client,
            data["access_token"],
            title="On day",
            repeat_weekdays=[scheduled_today],
        )
        off = _create_habit(
            client,
            data["access_token"],
            title="Off day",
            repeat_weekdays=[not_scheduled],
        )
        for habit in (on, off):
            _log(
                client,
                data["access_token"],
                habit["id"],
                date=today.isoformat(),
            )

        response = client.get(
            "/api/v1/habits/dashboard",
            headers=_auth(data["access_token"]),
        )
        by_title = {s["habit"]["title"]: s for s in response.json()["habits"]}
        assert by_title["On day"]["current_streak"] == 1
        assert by_title["Off day"]["current_streak"] == 0
        assert by_title["Off day"]["scheduled_7d"] == 0

    def test_rejects_invalid_timezone(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/habits/dashboard?timezone=Not/AZone",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422
