import logging
import uuid
from datetime import datetime
from datetime import time as dt_time
from datetime import timedelta
from typing import Protocol
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.calendar_block import CalendarBlock
from app.models.notification_preference import NotificationPreference
from app.models.task import Task
from app.models.task import TaskStatus
from app.models.user import User
from app.repositories import device_token_repository
from app.repositories import notification_repository
from app.schemas.notification import DeviceRegisterRequest
from app.schemas.notification import NotificationPreferenceUpdate

logger = logging.getLogger(__name__)


class PushSender(Protocol):
    def send(
        self, *, token: str, title: str, body: str, data: dict
    ) -> bool: ...


class LoggingPushSender:
    """Fallback sender used when APNs credentials are not configured."""

    def send(self, *, token: str, title: str, body: str, data: dict) -> bool:
        logger.info(
            "Push notification (transport not configured): title=%r body=%r data=%s token=%s",
            title,
            body,
            data,
            token[-8:],
        )
        return True


def _utc() -> ZoneInfo:
    return ZoneInfo("UTC")


class NotificationService:
    def __init__(
        self,
        db: Session,
        user_id: uuid.UUID | None = None,
        sender: PushSender | None = None,
    ) -> None:
        self.db = db
        self.user_id = user_id
        self.sender = sender or LoggingPushSender()

    # ------------------------------------------------------------------
    # Preferences
    # ------------------------------------------------------------------
    def get_preferences(self, user_id: uuid.UUID) -> NotificationPreference:
        preference = notification_repository.get_preference(
            self.db, user_id=user_id
        )
        if preference is None:
            preference = notification_repository.create_preference(
                self.db, user_id=user_id
            )
            self.db.commit()
            self.db.refresh(preference)
        return preference

    def update_preferences(
        self, user_id: uuid.UUID, data: NotificationPreferenceUpdate
    ) -> NotificationPreference:
        preference = self.get_preferences(user_id)
        preference = notification_repository.update_preference(
            self.db, preference, data
        )
        self.db.commit()
        self.db.refresh(preference)
        return preference

    # ------------------------------------------------------------------
    # Device registration
    # ------------------------------------------------------------------
    def register_device(
        self, user_id: uuid.UUID, data: DeviceRegisterRequest
    ) -> object:
        token = device_token_repository.upsert_device(
            self.db, user_id=user_id, data=data
        )
        self.db.commit()
        self.db.refresh(token)
        return token

    def unregister_device(self, user_id: uuid.UUID, device_id: str) -> bool:
        removed = device_token_repository.deactivate_device(
            self.db, user_id=user_id, device_id=device_id
        )
        self.db.commit()
        return removed

    # ------------------------------------------------------------------
    # Sending helpers
    # ------------------------------------------------------------------
    def _send(
        self, user_id: uuid.UUID, title: str, body: str, data: dict
    ) -> int:
        devices = device_token_repository.list_active_tokens(
            self.db, user_id=user_id
        )
        sent = 0
        for device in devices:
            try:
                self.sender.send(
                    token=device.token,
                    title=title,
                    body=body,
                    data=data,
                )
                sent += 1
            except Exception:  # pragma: no cover - defensive
                logger.exception(
                    "Failed to send notification to device %s",
                    device.device_id,
                )
        return sent

    def _enabled(self, user_id: uuid.UUID, flag: str) -> bool:
        preference = notification_repository.get_preference(
            self.db, user_id=user_id
        )
        if preference is None:
            return True
        return bool(getattr(preference, flag, True))

    def _user_timezone(self, user_id: uuid.UUID) -> ZoneInfo:
        name = device_token_repository.user_timezone(
            self.db, user_id=user_id
        )
        try:
            return ZoneInfo(name or "UTC")
        except Exception:  # pragma: no cover - defensive
            return _utc()

    def _local_bounds(
        self, now: datetime, zone: ZoneInfo
    ) -> tuple[datetime, datetime]:
        local_now = now.astimezone(zone)
        start = datetime(
            local_now.year,
            local_now.month,
            local_now.day,
            tzinfo=zone,
        )
        return start, start + timedelta(days=1)

    # ------------------------------------------------------------------
    # Background jobs
    # ------------------------------------------------------------------
    def run_morning_briefings(self, now: datetime | None = None) -> int:
        """Send a daily briefing to users whose local time matches their
        configured briefing time (defaults to 07:30)."""
        now = now or datetime.now(_utc())
        sent = 0
        users = list(self.db.scalars(select(User)).all())
        for user in users:
            if not self._enabled(user.id, "morning_briefing_enabled"):
                continue
            preference = notification_repository.get_preference(
                self.db, user_id=user.id
            )
            zone = self._user_timezone(user.id)
            local = now.astimezone(zone)
            briefing_time = (
                preference.morning_briefing_time
                if preference is not None
                else dt_time(hour=7, minute=30)
            )
            if (
                local.time().replace(second=0, microsecond=0)
                != briefing_time.replace(second=0, microsecond=0)
            ):
                continue
            body = self._build_briefing(user.id, zone, now)
            if body:
                self._send(
                    user.id,
                    "Good morning",
                    body,
                    {"type": "morning_briefing", "url": "app://today"},
                )
                sent += 1
        return sent

    def _build_briefing(
        self, user_id: uuid.UUID, zone: ZoneInfo, now: datetime
    ) -> str | None:
        start, end = self._local_bounds(now, zone)
        tasks = list(
            self.db.scalars(
                select(Task).where(
                    Task.user_id == user_id,
                    Task.is_archived.is_(False),
                    Task.status != TaskStatus.completed,
                )
            ).all()
        )
        if not tasks:
            return None
        high_priority = sum(1 for task in tasks if task.priority.value == "high")
        blocks = list(
            self.db.scalars(
                select(CalendarBlock).where(
                    CalendarBlock.user_id == user_id,
                    CalendarBlock.start_at >= start,
                    CalendarBlock.start_at < end,
                )
            ).all()
        )
        focus_minutes = sum(
            int((block.end_at - block.start_at).total_seconds() // 60)
            for block in blocks
        )
        deadline_today = [
            task
            for task in tasks
            if task.deadline is not None and start <= task.deadline < end
        ]
        parts = [
            f"You have {len(tasks)} task{'s' if len(tasks) != 1 else ''} to work on today."
        ]
        if high_priority:
            parts.append(f"{high_priority} high-priority.")
        if focus_minutes:
            parts.append(
                f"{focus_minutes} min scheduled for focused work."
            )
        if deadline_today:
            parts.append(
                f"{len(deadline_today)} due today."
            )
        return " ".join(parts)

    def run_deadline_reminders(self, now: datetime | None = None) -> int:
        """Remind users about tasks whose deadline falls within their lead
        window."""
        now = now or datetime.now(_utc())
        sent = 0
        users = list(self.db.scalars(select(User)).all())
        for user in users:
            if not self._enabled(user.id, "deadline_reminder_enabled"):
                continue
            preference = notification_repository.get_preference(
                self.db, user_id=user.id
            )
            lead_hours = (
                preference.deadline_reminder_lead_hours
                if preference is not None
                else 24
            )
            zone = self._user_timezone(user.id)
            local = now.astimezone(zone)
            start, _ = self._local_bounds(now, zone)
            cutoff = now + timedelta(hours=lead_hours)
            tasks = list(
                self.db.scalars(
                    select(Task).where(
                        Task.user_id == user.id,
                        Task.is_archived.is_(False),
                        Task.status != TaskStatus.completed,
                        Task.deadline.is_not(None),
                        Task.deadline >= start,
                        Task.deadline <= cutoff,
                    )
                ).all()
            )
            for task in tasks:
                due = task.deadline.astimezone(zone)
                self._send(
                    user.id,
                    "Deadline reminder",
                    f"“{task.title}” is due {self._format_due(due, local)}.",
                    {
                        "type": "deadline_reminder",
                        "task_id": str(task.id),
                        "url": "app://today",
                    },
                )
                sent += 1
        return sent

    def run_overdue_alerts(self, now: datetime | None = None) -> int:
        """Alert users about tasks that became overdue within the last 24h."""
        now = now or datetime.now(_utc())
        sent = 0
        users = list(self.db.scalars(select(User)).all())
        window_start = now - timedelta(hours=24)
        for user in users:
            if not self._enabled(user.id, "overdue_alerts_enabled"):
                continue
            zone = self._user_timezone(user.id)
            tasks = list(
                self.db.scalars(
                    select(Task).where(
                        Task.user_id == user.id,
                        Task.is_archived.is_(False),
                        Task.status != TaskStatus.completed,
                        Task.deadline.is_not(None),
                        Task.deadline >= window_start,
                        Task.deadline < now,
                    )
                ).all()
            )
            for task in tasks:
                due = task.deadline.astimezone(zone)
                self._send(
                    user.id,
                    "Overdue task",
                    f"“{task.title}” was due {self._format_due(due, now.astimezone(zone))}.",
                    {
                        "type": "overdue_alert",
                        "task_id": str(task.id),
                        "url": "app://today",
                    },
                )
                sent += 1
        return sent

    def notify_overcommitted(
        self,
        user_id: uuid.UUID,
        deferred_titles: list[str],
        required_hours: float,
        scheduleable_hours: float,
    ) -> int:
        """Event-driven alert when a proposed schedule cannot fit all tasks."""
        if not self._enabled(user_id, "reschedule_alerts_enabled"):
            return 0
        if deferred_titles:
            shown = ", ".join(deferred_titles[:3])
            suffix = " and more" if len(deferred_titles) > 3 else ""
            body = (
                f"{len(deferred_titles)} task(s) could not fit your schedule: "
                f"{shown}{suffix}. Defer, shorten, or reschedule."
            )
        else:
            body = (
                f"Your schedule needs {required_hours:.1f}h but only "
                f"{scheduleable_hours:.1f}h are free. Consider moving deadlines "
                "or reducing scope."
            )
        return self._send(
            user_id,
            "Your schedule needs attention",
            body,
            {"type": "reschedule_alert", "url": "app://today"},
        )

    @staticmethod
    def _format_due(due: datetime, local_now: datetime) -> str:
        if due.date() == local_now.date():
            return f"today at {due.strftime('%-I:%M %p')}"
        if due.date() == (local_now + timedelta(days=1)).date():
            return "tomorrow"
        return due.strftime("%b %d")


def run_all_jobs(db: Session, now: datetime | None = None) -> dict[str, int]:
    """Run every notification job once. Intended for cron/deploy workers."""
    service = NotificationService(db)
    now = now or datetime.now(_utc())
    return {
        "morning_briefings": service.run_morning_briefings(now),
        "deadline_reminders": service.run_deadline_reminders(now),
        "overdue_alerts": service.run_overdue_alerts(now),
    }
