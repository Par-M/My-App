import uuid
from datetime import datetime
from datetime import timedelta
from datetime import time as dt_time
from datetime import timezone

from app.db.database import SessionLocal
from app.models.device_token import DeviceToken
from app.models.notification_preference import NotificationPreference
from app.models.task import Task
from app.models.user import User
from app.services.notification_service import NotificationService

NOW = datetime.now(timezone.utc)


class FakeSender:
    def __init__(self):
        self.sent: list[dict] = []

    def send(self, *, token: str, title: str, body: str, data: dict) -> bool:
        self.sent.append(
            {"token": token, "title": title, "body": body, "data": data}
        )
        return True


def _login(client, email="notify@example.com", name="Notify"):
    response = client.post(
        "/api/v1/auth/dev",
        json={"name": name, "email": email},
    )
    assert response.status_code == 200
    return response.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _create_user(email="job@example.com") -> uuid.UUID:
    db = SessionLocal()
    try:
        user = User(
            provider="dev",
            provider_user_id=email,
            email=email,
            name="Job User",
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        return user.id
    finally:
        db.close()


class TestDeviceRegistration:
    def test_register_device(self, client):
        data = _login(client)
        response = client.post(
            "/api/v1/devices/register",
            json={
                "device_id": "iphone-1",
                "token": "apns-token-abc",
                "platform": "ios",
                "timezone": "America/New_York",
            },
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["device_id"] == "iphone-1"
        assert body["token"] == "apns-token-abc"
        assert body["timezone"] == "America/New_York"
        assert body["is_active"] is True

    def test_register_updates_existing_token(self, client):
        data = _login(client)
        headers = _auth(data["access_token"])
        payload = {"device_id": "iphone-1", "token": "old-token"}
        assert client.post(
            "/api/v1/devices/register", json=payload, headers=headers
        ).status_code == 200
        response = client.post(
            "/api/v1/devices/register",
            json={**payload, "token": "new-token", "timezone": "UTC"},
            headers=headers,
        )
        assert response.status_code == 200
        assert response.json()["token"] == "new-token"
        db = SessionLocal()
        try:
            tokens = db.query(DeviceToken).all()
            assert len(tokens) == 1
        finally:
            db.close()

    def test_unregister_device(self, client):
        data = _login(client)
        headers = _auth(data["access_token"])
        assert client.post(
            "/api/v1/devices/register",
            json={"device_id": "iphone-1", "token": "token"},
            headers=headers,
        ).status_code == 200
        response = client.delete(
            "/api/v1/devices/iphone-1", headers=headers
        )
        assert response.status_code == 204

    def test_unregister_missing_device_404(self, client):
        data = _login(client)
        response = client.delete(
            "/api/v1/devices/unknown", headers=_auth(data["access_token"])
        )
        assert response.status_code == 404


class TestNotificationPreferencesEndpoint:
    def test_get_defaults(self, client):
        data = _login(client)
        response = client.get(
            "/api/v1/notifications/preferences",
            headers=_auth(data["access_token"]),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["morning_briefing_enabled"] is True
        assert body["morning_briefing_time"] == "07:30:00"
        assert body["deadline_reminder_lead_hours"] == 24

    def test_patch_preferences(self, client):
        data = _login(client)
        headers = _auth(data["access_token"])
        response = client.patch(
            "/api/v1/notifications/preferences",
            json={
                "morning_briefing_enabled": False,
                "morning_briefing_time": "08:00:00",
                "deadline_reminder_lead_hours": 48,
            },
            headers=headers,
        )
        assert response.status_code == 200
        body = response.json()
        assert body["morning_briefing_enabled"] is False
        assert body["morning_briefing_time"] == "08:00:00"
        assert body["deadline_reminder_lead_hours"] == 48


class TestMorningBriefingJob:
    def test_sends_when_local_time_matches(self):
        user_id = _create_user("brief@example.com")
        db = SessionLocal()
        try:
            db.add(
                NotificationPreference(
                    user_id=user_id,
                    morning_briefing_time=dt_time(hour=7, minute=30),
                )
            )
            db.add(
                Task(
                    user_id=user_id,
                    title="Ship report",
                    priority="high",
                )
            )
            db.add(
                DeviceToken(
                    user_id=user_id,
                    device_id="iphone-1",
                    token="token-1",
                    timezone="UTC",
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            now = NOW.replace(hour=7, minute=30, second=0, microsecond=0)
            sent = service.run_morning_briefings(now)

            assert sent == 1
            assert sender.sent[0]["data"]["type"] == "morning_briefing"
            assert "1 task" in sender.sent[0]["body"]
        finally:
            db.close()

    def test_skips_when_time_mismatch(self):
        user_id = _create_user("brief2@example.com")
        db = SessionLocal()
        try:
            db.add(
                NotificationPreference(
                    user_id=user_id,
                    morning_briefing_time=dt_time(hour=7, minute=30),
                )
            )
            db.add(
                DeviceToken(
                    user_id=user_id,
                    device_id="iphone-1",
                    token="token-1",
                    timezone="UTC",
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.run_morning_briefings(NOW.replace(hour=9, minute=0))

            assert sent == 0
        finally:
            db.close()

    def test_skips_when_disabled(self):
        user_id = _create_user("brief3@example.com")
        db = SessionLocal()
        try:
            db.add(
                NotificationPreference(
                    user_id=user_id,
                    morning_briefing_enabled=False,
                    morning_briefing_time=dt_time(hour=7, minute=30),
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.run_morning_briefings(
                NOW.replace(hour=7, minute=30)
            )
            assert sent == 0
        finally:
            db.close()


class TestDeadlineReminderJob:
    def test_reminds_within_lead_window(self):
        user_id = _create_user("deadline@example.com")
        db = SessionLocal()
        try:
            db.add(
                NotificationPreference(
                    user_id=user_id,
                    deadline_reminder_lead_hours=24,
                )
            )
            db.add(
                Task(
                    user_id=user_id,
                    title="Pay invoice",
                    deadline=NOW + timedelta(hours=6),
                )
            )
            db.add(
                DeviceToken(
                    user_id=user_id,
                    device_id="iphone-1",
                    token="token-1",
                    timezone="UTC",
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.run_deadline_reminders(NOW)

            assert sent == 1
            assert sender.sent[0]["data"]["type"] == "deadline_reminder"
            assert sender.sent[0]["data"]["task_id"]
            assert "Pay invoice" in sender.sent[0]["body"]
        finally:
            db.close()

    def test_skips_outside_window(self):
        user_id = _create_user("deadline2@example.com")
        db = SessionLocal()
        try:
            db.add(
                NotificationPreference(
                    user_id=user_id,
                    deadline_reminder_lead_hours=24,
                )
            )
            db.add(
                Task(
                    user_id=user_id,
                    title="Far deadline",
                    deadline=NOW + timedelta(days=3),
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.run_deadline_reminders(NOW)
            assert sent == 0
        finally:
            db.close()


class TestOverdueJob:
    def test_alerts_recently_overdue(self):
        user_id = _create_user("overdue@example.com")
        db = SessionLocal()
        try:
            db.add(
                Task(
                    user_id=user_id,
                    title="File taxes",
                    deadline=NOW - timedelta(hours=2),
                )
            )
            db.add(
                DeviceToken(
                    user_id=user_id,
                    device_id="iphone-1",
                    token="token-1",
                    timezone="UTC",
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.run_overdue_alerts(NOW)

            assert sent == 1
            assert sender.sent[0]["data"]["type"] == "overdue_alert"
            assert "File taxes" in sender.sent[0]["body"]
        finally:
            db.close()

    def test_skips_completed_tasks(self):
        user_id = _create_user("overdue2@example.com")
        db = SessionLocal()
        try:
            db.add(
                Task(
                    user_id=user_id,
                    title="Done late",
                    deadline=NOW - timedelta(hours=2),
                    status="completed",
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.run_overdue_alerts(NOW)
            assert sent == 0
        finally:
            db.close()


class TestOvercommittedAlert:
    def test_sends_with_deferred_tasks(self):
        user_id = _create_user("overcom@example.com")
        db = SessionLocal()
        try:
            db.add(
                DeviceToken(
                    user_id=user_id,
                    device_id="iphone-1",
                    token="token-1",
                    timezone="UTC",
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.notify_overcommitted(
                user_id,
                deferred_titles=["Write docs", "Refactor auth"],
                required_hours=8.0,
                scheduleable_hours=4.0,
            )

            assert sent == 1
            assert sender.sent[0]["data"]["type"] == "reschedule_alert"
            assert "Write docs" in sender.sent[0]["body"]
        finally:
            db.close()

    def test_respects_disabled_preference(self):
        user_id = _create_user("overcom2@example.com")
        db = SessionLocal()
        try:
            db.add(
                NotificationPreference(
                    user_id=user_id,
                    reschedule_alerts_enabled=False,
                )
            )
            db.commit()

            sender = FakeSender()
            service = NotificationService(db, sender=sender)
            sent = service.notify_overcommitted(
                user_id, deferred_titles=["x"], required_hours=8.0, scheduleable_hours=4.0
            )
            assert sent == 0
        finally:
            db.close()
