from datetime import datetime
from datetime import timedelta
from datetime import timezone

from app.services.recommendation_service import split_description_into_steps
from app.services.recommendation_service import split_task_into_parts

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
