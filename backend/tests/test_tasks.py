import uuid
from datetime import datetime
from datetime import timedelta
from datetime import timezone

from app.models.task import TaskPriority
from app.models.task import TaskStatus

NOW = datetime.now(timezone.utc)
FUTURE = NOW + timedelta(days=1)
PAST = NOW - timedelta(days=1)


def _login(client, email="parthiv@example.com", name="Parthiv"):
    response = client.post(
        "/api/v1/auth/dev",
        json={"name": name, "email": email},
    )
    assert response.status_code == 200
    return response.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _create(client, token, **overrides):
    payload = {"title": "Buy groceries"}
    payload.update(overrides)
    return client.post("/api/v1/tasks", json=payload, headers=_auth(token))


class TestCreateTask:
    def test_requires_authentication(self, client):
        response = client.post("/api/v1/tasks", json={"title": "x"})
        assert response.status_code == 401

    def test_creates_task_with_defaults(self, client):
        data = _login(client)
        response = _create(client, data["access_token"])

        assert response.status_code == 201
        body = response.json()
        assert body["title"] == "Buy groceries"
        assert body["priority"] == "medium"
        assert body["status"] == "pending"
        assert body["is_archived"] is False
        assert body["description"] is None
        assert body["deadline"] is None
        assert body["category"] is None
        assert body["user_id"] == data["user"]["id"]
        assert body["created_at"]

    def test_creates_task_with_full_payload(self, client):
        data = _login(client)
        response = _create(
            client,
            data["access_token"],
            title="  Ship v1  ",
            description="Ship the release",
            deadline=FUTURE.isoformat(),
            priority="high",
            status="in_progress",
            estimated_duration=90,
            category="Work",
            notes="Notify the team",
        )

        assert response.status_code == 201
        body = response.json()
        assert body["title"] == "Ship v1"
        assert body["description"] == "Ship the release"
        assert body["priority"] == "high"
        assert body["status"] == "in_progress"
        assert body["estimated_duration"] == 90
        assert body["category"] == "Work"
        assert body["notes"] == "Notify the team"

    def test_rejects_blank_title(self, client):
        data = _login(client)
        response = _create(client, data["access_token"], title="   ")
        assert response.status_code == 422

    def test_rejects_invalid_priority(self, client):
        data = _login(client)
        response = _create(client, data["access_token"], priority="urgent")
        assert response.status_code == 422

    def test_rejects_negative_duration(self, client):
        data = _login(client)
        response = _create(
            client, data["access_token"], estimated_duration=-5
        )
        assert response.status_code == 422

    def test_creates_task_with_repeat_weekdays(self, client):
        data = _login(client)
        response = _create(
            client,
            data["access_token"],
            repeat_weekdays=[1, 3, 1, 5],
        )
        assert response.status_code == 201
        body = response.json()
        assert body["repeat_weekdays"] == [1, 3, 5]

    def test_defaults_repeat_weekdays_to_none(self, client):
        data = _login(client)
        response = _create(client, data["access_token"])
        assert response.status_code == 201
        assert response.json()["repeat_weekdays"] is None

    def test_empty_repeat_weekdays_becomes_none(self, client):
        data = _login(client)
        response = _create(client, data["access_token"], repeat_weekdays=[])
        assert response.status_code == 201
        assert response.json()["repeat_weekdays"] is None

    def test_rejects_out_of_range_weekday(self, client):
        data = _login(client)
        response = _create(client, data["access_token"], repeat_weekdays=[7])
        assert response.status_code == 422


class TestGetTask:
    def test_requires_authentication(self, client):
        response = client.get(f"/api/v1/tasks/{uuid.uuid4()}")
        assert response.status_code == 401

    def test_returns_own_task(self, client):
        data = _login(client)
        created = _create(client, data["access_token"]).json()

        response = client.get(
            f"/api/v1/tasks/{created['id']}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["id"] == created["id"]

    def test_returns_404_for_unknown_task(self, client):
        data = _login(client)
        response = client.get(
            f"/api/v1/tasks/{uuid.uuid4()}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404

    def test_returns_422_for_invalid_id(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/tasks/not-a-uuid",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422

    def test_user_cannot_see_another_users_task(self, client):
        owner = _login(client, "owner@example.com")
        created = _create(client, owner["access_token"]).json()

        other = _login(client, "other@example.com")
        response = client.get(
            f"/api/v1/tasks/{created['id']}",
            headers=_auth(other["access_token"]),
        )
        assert response.status_code == 404


class TestListTasks:
    def test_returns_empty_list(self, client):
        data = _login(client)
        response = client.get("/api/v1/tasks", headers=_auth(data["access_token"]))

        assert response.status_code == 200
        assert response.json() == {"items": [], "total": 0}

    def test_returns_only_own_tasks(self, client):
        owner = _login(client, "owner@example.com")
        _create(client, owner["access_token"], title="Owner task")

        other = _login(client, "other@example.com")
        _create(client, other["access_token"], title="Other task")

        response = client.get(
            "/api/v1/tasks", headers=_auth(owner["access_token"])
        )
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "Owner task"

    def test_excludes_archived_by_default(self, client):
        data = _login(client)
        created = _create(client, data["access_token"], title="Archived later").json()
        client.post(
            f"/api/v1/tasks/{created['id']}/archive",
            headers=_auth(data["access_token"]),
        )

        response = client.get("/api/v1/tasks", headers=_auth(data["access_token"]))
        assert response.json()["total"] == 0

    def test_include_archived(self, client):
        data = _login(client)
        created = _create(client, data["access_token"], title="Archived later").json()
        client.post(
            f"/api/v1/tasks/{created['id']}/archive",
            headers=_auth(data["access_token"]),
        )

        response = client.get(
            "/api/v1/tasks?archived=true",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 1

    def test_filters_by_since(self, client):
        data = _login(client)
        created = _create(client, data["access_token"], title="Sync me").json()
        created_at = created["updated_at"]
        _create(client, data["access_token"], title="Stale")

        response = client.get(
            f"/api/v1/tasks?since={created_at}",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert body["total"] == 2
        assert created["id"] in {item["id"] for item in body["items"]}

        later = datetime.fromisoformat(
            created_at.replace("Z", "+00:00")
        ) + timedelta(days=1)
        response = client.get(
            f"/api/v1/tasks?since={later.isoformat().replace('+00:00', 'Z')}",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 0


class TestSearchTasks:
    def test_search_matches_title(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="Buy groceries")
        _create(client, data["access_token"], title="Write report")

        response = client.get(
            "/api/v1/tasks?search=groceries",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "Buy groceries"

    def test_search_matches_notes(self, client):
        data = _login(client)
        _create(client, data["access_token"], notes="Call the dentist")
        _create(client, data["access_token"], notes="Water the plants")

        response = client.get(
            "/api/v1/tasks?search=dentist",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 1

    def test_search_is_case_insensitive(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="Buy GROCERIES")

        response = client.get(
            "/api/v1/tasks?search=groceries",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 1


class TestFilterTasks:
    def test_filter_by_priority(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="Low", priority="low")
        _create(client, data["access_token"], title="High", priority="high")

        response = client.get(
            "/api/v1/tasks?priority=high",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "High"

    def test_filter_by_status(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="Done", status="completed")
        _create(client, data["access_token"], title="Todo", status="pending")

        response = client.get(
            "/api/v1/tasks?status=completed",
            headers=_auth(data["access_token"]),
        )
        body = response.json()
        assert body["total"] == 1
        assert body["items"][0]["title"] == "Done"

    def test_filter_by_category(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="Work item", category="Work")
        _create(client, data["access_token"], title="Home item", category="Home")

        response = client.get(
            "/api/v1/tasks?category=Work",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 1

    def test_combined_filters(self, client):
        data = _login(client)
        _create(client, data["access_token"], title="A", priority="high", category="Work")
        _create(client, data["access_token"], title="B", priority="high", category="Home")
        _create(client, data["access_token"], title="C", priority="low", category="Work")

        response = client.get(
            "/api/v1/tasks?priority=high&category=Work",
            headers=_auth(data["access_token"]),
        )
        assert response.json()["total"] == 1


class TestSortTasks:
    def test_sorts_by_deadline_ascending(self, client):
        data = _login(client)
        later = _create(
            client, data["access_token"], title="Later", deadline=FUTURE.isoformat()
        ).json()
        sooner = _create(
            client, data["access_token"], title="Sooner", deadline=PAST.isoformat()
        ).json()

        response = client.get(
            "/api/v1/tasks?sort=deadline",
            headers=_auth(data["access_token"]),
        )
        titles = [item["id"] for item in response.json()["items"]]
        assert titles == [sooner["id"], later["id"]]

    def test_sorts_by_deadline_descending(self, client):
        data = _login(client)
        later = _create(
            client, data["access_token"], title="Later", deadline=FUTURE.isoformat()
        ).json()
        sooner = _create(
            client, data["access_token"], title="Sooner", deadline=PAST.isoformat()
        ).json()

        response = client.get(
            "/api/v1/tasks?sort=deadline&order=desc",
            headers=_auth(data["access_token"]),
        )
        titles = [item["id"] for item in response.json()["items"]]
        assert titles == [later["id"], sooner["id"]]

    def test_sorts_by_priority(self, client):
        data = _login(client)
        low = _create(client, data["access_token"], title="Low", priority="low").json()
        high = _create(client, data["access_token"], title="High", priority="high").json()

        response = client.get(
            "/api/v1/tasks?sort=priority",
            headers=_auth(data["access_token"]),
        )
        titles = [item["id"] for item in response.json()["items"]]
        assert titles == [low["id"], high["id"]]

    def test_rejects_unknown_sort(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/tasks?sort=banana",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422

    def test_rejects_bad_order(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/tasks?order=sideways",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 422


class TestUpdateTask:
    def test_partial_update(self, client):
        data = _login(client)
        created = _create(client, data["access_token"], title="Original").json()

        response = client.patch(
            f"/api/v1/tasks/{created['id']}",
            json={"title": "Updated", "priority": "high"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["title"] == "Updated"
        assert body["priority"] == "high"
        assert body["status"] == "pending"

    def test_clear_deadline(self, client):
        data = _login(client)
        created = _create(
            client, data["access_token"], deadline=FUTURE.isoformat()
        ).json()

        response = client.patch(
            f"/api/v1/tasks/{created['id']}",
            json={"deadline": None},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["deadline"] is None

    def test_update_requires_authentication(self, client):
        response = client.patch(
            f"/api/v1/tasks/{uuid.uuid4()}",
            json={"title": "x"},
        )
        assert response.status_code == 401

    def test_update_unknown_task_returns_404(self, client):
        data = _login(client)
        response = client.patch(
            f"/api/v1/tasks/{uuid.uuid4()}",
            json={"title": "x"},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404

    def test_user_cannot_update_another_users_task(self, client):
        owner = _login(client, "owner@example.com")
        created = _create(client, owner["access_token"]).json()

        other = _login(client, "other@example.com")
        response = client.patch(
            f"/api/v1/tasks/{created['id']}",
            json={"title": "Hijacked"},
            headers=_auth(other["access_token"]),
        )
        assert response.status_code == 404

    def test_update_repeat_weekdays(self, client):
        data = _login(client)
        created = _create(client, data["access_token"]).json()
        assert created["repeat_weekdays"] is None

        response = client.patch(
            f"/api/v1/tasks/{created['id']}",
            json={"repeat_weekdays": [0, 6]},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["repeat_weekdays"] == [0, 6]

    def test_clear_repeat_weekdays(self, client):
        data = _login(client)
        created = _create(
            client, data["access_token"], repeat_weekdays=[1, 2]
        ).json()

        response = client.patch(
            f"/api/v1/tasks/{created['id']}",
            json={"repeat_weekdays": None},
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["repeat_weekdays"] is None


class TestDeleteTask:
    def test_delete_task(self, client):
        data = _login(client)
        created = _create(client, data["access_token"]).json()

        response = client.delete(
            f"/api/v1/tasks/{created['id']}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        assert response.json()["message"] == "Task deleted"

        gone = client.get(
            f"/api/v1/tasks/{created['id']}",
            headers=_auth(data["access_token"]),
        )
        assert gone.status_code == 404

    def test_delete_unknown_task_returns_404(self, client):
        data = _login(client)
        response = client.delete(
            f"/api/v1/tasks/{uuid.uuid4()}",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404


class TestArchiveRestore:
    def test_archive_and_restore(self, client):
        data = _login(client)
        created = _create(client, data["access_token"]).json()

        archived = client.post(
            f"/api/v1/tasks/{created['id']}/archive",
            headers=_auth(data["access_token"]),
        )
        assert archived.status_code == 200
        assert archived.json()["is_archived"] is True

        listed = client.get(
            "/api/v1/tasks", headers=_auth(data["access_token"])
        )
        assert listed.json()["total"] == 0

        restored = client.post(
            f"/api/v1/tasks/{created['id']}/restore",
            headers=_auth(data["access_token"]),
        )
        assert restored.status_code == 200
        assert restored.json()["is_archived"] is False

        listed = client.get(
            "/api/v1/tasks", headers=_auth(data["access_token"])
        )
        assert listed.json()["total"] == 1

    def test_archive_unknown_task_returns_404(self, client):
        data = _login(client)
        response = client.post(
            f"/api/v1/tasks/{uuid.uuid4()}/archive",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 404
