import importlib
from datetime import datetime
from datetime import timedelta
from datetime import timezone

import pytest

from app.services.recommendation_service import split_description_into_steps
from app.services.recommendation_service import split_task_into_parts


def _fake_now() -> datetime:
    # Fixed mid-morning UTC so "today's free time" always contains a usable
    # work window regardless of when CI happens to run (the daily endpoint
    # clamps today's window to the current time, so runs near the evening
    # boundary used to yield available_minutes == 0 and flake).
    return datetime(2026, 9, 22, 9, 0, 0, tzinfo=timezone.utc)


class _FakeDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        return _fake_now()


@pytest.fixture(autouse=True)
def _freeze_clock(monkeypatch):
    for module_name in (
        "app.services.recommendation_service",
        "app.services.scheduling.free_slots",
    ):
        monkeypatch.setattr(
            importlib.import_module(module_name), "datetime", _FakeDatetime
        )


NOW = datetime.now(timezone.utc)


def _login(client, email="rec@example.com", name="Rec"):
    response = client.post(
        "/api/v1/auth/dev",
        json={"name": name, "email": email},
    )
    assert response.status_code == 200
    return response.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _create(client, token, **overrides):
    payload = {"title": "Write report"}
    payload.update(overrides)
    response = client.post("/api/v1/tasks", json=payload, headers=_auth(token))
    assert response.status_code == 201
    return response.json()


class TestSplitHelpers:
    def test_numbered_steps(self):
        steps = split_description_into_steps(
            "1. Gather data\n2. Analyze\n3. Write summary"
        )
        assert len(steps) == 3
        assert steps[0] == "Gather data"

    def test_bullet_steps(self):
        steps = split_description_into_steps("- Draft outline\n- Review sources")
        assert len(steps) == 2

    def test_prose_sentences(self):
        steps = split_description_into_steps("First do research. Then write it up.")
        assert len(steps) == 2

    def test_chunk_without_description(self):
        parts = split_task_into_parts("Big task", None, 200)
        assert len(parts) == 3
        assert sum(p["minutes"] for p in parts) == 200

    def test_single_part_small_task(self):
        parts = split_task_into_parts("Quick", None, 30)
        assert len(parts) == 1

    def test_description_parts_cover_total(self):
        description = "Step one here. Step two follows. Step three ends it."
        parts = split_task_into_parts("Task", description, 90)
        assert len(parts) == 3
        assert sum(p["minutes"] for p in parts) == 90


class TestDailyRecommendationsEndpoint:
    def test_requires_authentication(self, client):
        response = client.post("/api/v1/recommendations/daily", json={})
        assert response.status_code == 401

    def test_accepts_iso_datetime_strings(self, client):
        data = _login(client)
        _create(client, data["access_token"], estimated_duration=60)

        response = client.post(
            "/api/v1/recommendations/daily",
            json={
                "timezone": "UTC",
                "start_date": "2026-08-22T07:00:00Z",
                "end_date": "2026-08-29T07:00:00Z",
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200

    def test_recommends_tasks_for_today(self, client):
        data = _login(client)
        _create(client, data["access_token"], estimated_duration=60)

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        today = body["days"][0]
        assert today["available_minutes"] > 0
        assert len(today["items"]) >= 1
        item = today["items"][0]
        assert item["task_title"] == "Write report"
        assert item["minutes"] == 60

    def test_scheduled_tasks_are_not_recommended(self, client):
        from datetime import timedelta

        data = _login(client)
        future = datetime.now(timezone.utc) + timedelta(days=30)
        _create(
            client,
            data["access_token"],
            title="Fixed Sept event",
            estimated_duration=60,
            start_at=future.isoformat(),
            end_at=(future + timedelta(hours=1)).isoformat(),
        )
        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        items = [
            item
            for day in response.json()["days"]
            for item in day["items"]
        ]
        assert all(item["task_title"] != "Fixed Sept event" for item in items)


    def test_completed_tasks_not_recommended(self, client):
        data = _login(client)
        created = _create(
            client,
            data["access_token"],
            estimated_duration=60,
        )
        client.post(
            f"/api/v1/tasks/{created['id']}/complete",
            json={},
            headers=_auth(data["access_token"]),
        )

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        items = [i for day in response.json()["days"] for i in day["items"]]
        assert all(i["task_title"] != "Write report" for i in items)

    def test_priority_ordering(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="Low first", priority="low")
        _create(client, data["access_token"], title="High later", priority="high")

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        titles = [i["task_title"] for i in response.json()["days"][0]["items"]]
        if "High later" in titles and "Low first" in titles:
            assert titles.index("High later") < titles.index("Low first")

    def test_deadline_ordering(self, client):
        data = _login(client)
        soon = (NOW + timedelta(days=1)).isoformat()
        late = (NOW + timedelta(days=10)).isoformat()
        _create(client, data["access_token"], title="Late deadline", deadline=late)
        _create(client, data["access_token"], title="Soon deadline", deadline=soon)

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        titles = [i["task_title"] for i in response.json()["days"][0]["items"]]
        if "Soon deadline" in titles and "Late deadline" in titles:
            assert titles.index("Soon deadline") < titles.index("Late deadline")

    def test_partially_completed_task_recommends_only_amount_left(self, client):
        data = _login(client)
        created = _create(
            client,
            data["access_token"],
            title="Partly done",
            estimated_duration=60,
        )
        client.patch(
            f"/api/v1/tasks/{created['id']}",
            json={"actual_duration": 30},
            headers=_auth(data["access_token"]),
        )

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        items = [
            item
            for day in response.json()["days"]
            for item in day["items"]
        ]
        part_items = [i for i in items if i["task_title"] == "Partly done"]
        assert part_items
        assert sum(i["minutes"] for i in part_items) == 30

    def test_fully_completed_task_not_recommended(self, client):
        data = _login(client)
        created = _create(
            client,
            data["access_token"],
            title="All done",
            estimated_duration=60,
        )
        client.patch(
            f"/api/v1/tasks/{created['id']}",
            json={"actual_duration": 60},
            headers=_auth(data["access_token"]),
        )

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        items = [
            item
            for day in response.json()["days"]
            for item in day["items"]
        ]
        assert all(item["task_title"] != "All done" for item in items)

    def test_work_does_not_cram_into_earliest_day(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="A", estimated_duration=60)
        _create(client, data["access_token"], title="B", estimated_duration=60)
        _create(client, data["access_token"], title="C", estimated_duration=60)

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        days = response.json()["days"]
        titles = [i["task_title"] for i in days[0]["items"]]
        assert titles == ["A"]

    def test_far_deadline_task_spreads_before_deadline(self, client):
        data = _login(client)
        far = (NOW + timedelta(days=14)).isoformat()
        near = (NOW + timedelta(days=1)).isoformat()
        _create(client, data["access_token"], title="Near", estimated_duration=60, deadline=near)
        _create(client, data["access_token"], title="Far", estimated_duration=480, deadline=far)

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        days = response.json()["days"]
        far_day_indices = [
            index
            for index, day in enumerate(days)
            if any(i["task_title"] == "Far" for i in day["items"])
        ]
        assert far_day_indices[0] > 0
        assert sum(
            i["minutes"]
            for day in days
            for i in day["items"]
            if i["task_title"] == "Far"
        ) == 480

    def test_parts_scheduled_in_order(self, client):
        data = _login(client)
        far = (NOW + timedelta(days=14)).isoformat()
        _create(
            client,
            data["access_token"],
            title="Big build",
            estimated_duration=540,
            deadline=far,
        )

        response = client.post(
            "/api/v1/recommendations/daily",
            json={"timezone": "UTC"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        scheduled = [
            (day_index, item)
            for day_index, day in enumerate(body["days"])
            for item in day["items"]
            if item["task_title"] == "Big build"
        ]
        assert scheduled
        assert sum(item["minutes"] for _, item in scheduled) == 540
        indices = [item["part_index"] for _, item in scheduled]
        assert indices == sorted(indices), (
            "parts must be scheduled in order (part 9 must never appear "
            "before parts 1-8)"
        )

    def test_parts_of_blocked_task_not_forceplaced(self, client):
        # If an earlier part cannot fit anywhere, later parts of the same task
        # must not show a time block on their own.
        data = _login(client)
        far = (NOW + timedelta(days=14)).isoformat()
        _create(
            client,
            data["access_token"],
            title="One-shot",
            estimated_duration=540,
            deadline=far,
        )

        midnight = NOW.replace(hour=0, minute=0, second=0, microsecond=0)
        response = client.post(
            "/api/v1/recommendations/daily",
            json={
                "timezone": "UTC",
                "start_date": midnight.date().isoformat(),
                "end_date": midnight.date().isoformat(),
                "busy_times": [
                    {
                        "start": midnight.isoformat(),
                        "end": (midnight + timedelta(hours=23)).isoformat(),
                    }
                ],
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["days"][0]["items"] == []
        assert len(body["unscheduled"]) == 6

    def test_big_multi_part_tasks_still_fit(self, client):
        # Regression: many large multi-part tasks with a near deadline must all
        # fit into the remaining free time (before the indexing change, empty
        # days were left blank and parts spilled into "doesn't fit this window").
        data = _login(client)
        deadline = (NOW + timedelta(days=4)).isoformat()
        for title, duration, priority in [
            ("Circuit notes 8-15", 720, "high"),
            ("Circuit TD problem set", 360, "medium"),
            ("Tutorial part 7/8", 300, "medium"),
            ("Notes + problem set/tutorial part 10-15", 900, "low"),
        ]:
            _create(
                client,
                data["access_token"],
                title=title,
                estimated_duration=duration,
                priority=priority,
                deadline=deadline,
            )

        start = NOW.replace(hour=0, minute=0, second=0, microsecond=0)
        busy_times = []
        for offset in range(7):
            day = start + timedelta(days=offset)
            busy_times.append(
                {
                    "start": (day + timedelta(hours=9)).isoformat(),
                    "end": (day + timedelta(hours=11)).isoformat(),
                }
            )
            busy_times.append(
                {
                    "start": (day + timedelta(hours=13)).isoformat(),
                    "end": (day + timedelta(hours=17)).isoformat(),
                }
            )

        response = client.post(
            "/api/v1/recommendations/daily",
            json={
                "timezone": "UTC",
                "start_date": start.date().isoformat(),
                "end_date": (start + timedelta(days=6)).date().isoformat(),
                "busy_times": busy_times,
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["unscheduled"] == [], (
            "all parts must fit; nothing may spill into unscheduled"
        )
        # Each task's parts appear in order across the window.
        for day_index in range(len(body["days"])):
            seen: dict[str, int] = {}
            for item in body["days"][day_index]["items"]:
                previous = seen.get(item["task_title"])
                assert previous is None or item["part_index"] > previous, (
                    f"{item['task_title']} parts out of order on "
                    f'{body["days"][day_index]["date"]}'
                )
                seen[item["task_title"]] = item["part_index"]

    def test_busy_time_defers_to_unscheduled(self, client):
        data = _login(client)
        _create(client, data["access_token"], estimated_duration=120)

        midnight = NOW.replace(hour=0, minute=0, second=0, microsecond=0)
        response = client.post(
            "/api/v1/recommendations/daily",
            json={
                "timezone": "UTC",
                "start_date": midnight.date().isoformat(),
                "end_date": midnight.date().isoformat(),
                "busy_times": [
                    {
                        "start": midnight.isoformat(),
                        "end": (midnight + timedelta(hours=23)).isoformat(),
                    }
                ],
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["days"][0]["items"] == []
        assert len(body["unscheduled"]) == 2


class TestBreakdownEndpoint:
    def test_breaks_down_description(self, client):
        data = _login(client)
        task = _create(
            client,
            data["access_token"],
            title="Report",
            estimated_duration=90,
            description="1. Collect data\n2. Build charts\n3. Write prose",
        )

        response = client.post(
            f"/api/v1/recommendations/breakdown/{task['id']}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert len(body["parts"]) == 3
        assert body["source"] == "description"
        assert sum(p["minutes"] for p in body["parts"]) == 90

    def test_chunks_without_description(self, client):
        data = _login(client)
        task = _create(
            client,
            data["access_token"],
            title="Big job",
            estimated_duration=180,
        )

        response = client.post(
            f"/api/v1/recommendations/breakdown/{task['id']}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert len(body["parts"]) == 2
        assert sum(p["minutes"] for p in body["parts"]) == 180

    def test_unknown_task_404(self, client):
        data = _login(client)
        response = client.post(
            "/api/v1/recommendations/breakdown/00000000-0000-0000-0000-000000000000",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404
