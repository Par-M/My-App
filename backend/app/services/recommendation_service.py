import re
import uuid
from datetime import date
from datetime import datetime
from datetime import timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.task import Task
from app.models.task import TaskPriority
from app.models.task import TaskStatus
from app.models.user_preference import UserPreference
from app.schemas.calendar import BusyTime
from app.services.scheduling.context import TimeSlot
from app.services.scheduling.free_slots import find_free_slots

PRIORITY_WEIGHT = {
    TaskPriority.high: 0,
    TaskPriority.medium: 1,
    TaskPriority.low: 2,
}

MAX_PART_MINUTES = 90
MIN_PART_MINUTES = 15

_STEP_LINE = re.compile(r"^\s*(?:\d+[.)\]]|[-*•])\s+")


def _utc_now() -> datetime:
    from datetime import timezone

    return datetime.now(timezone.utc)


def split_description_into_steps(description: str) -> list[str]:
    """Extract ordered steps from a task description.

    Numbered lists ("1.", "1)"), bullets ("- ", "* ", "•") each become a step.
    Plain prose is split into sentences. Blank lines are dropped.
    """
    lines = [line.strip() for line in description.splitlines()]
    stepped = [
        _STEP_LINE.sub("", line).strip()
        for line in lines
        if _STEP_LINE.match(line)
    ]
    if len(stepped) >= 2:
        return [step for step in stepped if step]

    prose = " ".join(line for line in lines if line and not _STEP_LINE.match(line))
    sentences = [
        sentence.strip()
        for sentence in re.split(r"(?<=[.!?;])\s+", prose)
        if sentence.strip()
    ]
    return sentences


def split_task_into_parts(
    title: str,
    description: str | None,
    duration_minutes: int,
) -> list[dict]:
    """Break a task into parts.

    Description steps become named parts (duration split evenly). Without a
    usable description the task is chunked into <= MAX_PART_MINUTES pieces.
    """
    total = max(MIN_PART_MINUTES, duration_minutes)

    if description:
        steps = split_description_into_steps(description)
        if len(steps) >= 2:
            per_part = max(MIN_PART_MINUTES, round(total / len(steps)))
            parts = []
            remaining = total
            for index, step in enumerate(steps):
                minutes = per_part if index < len(steps) - 1 else remaining
                minutes = max(MIN_PART_MINUTES, min(minutes, remaining))
                if minutes <= 0:
                    break
                label = step if len(step) <= 80 else step[:77] + "…"
                parts.append(
                    {"index": index, "title": label, "minutes": minutes}
                )
                remaining -= minutes
            if parts:
                return parts

    chunk = min(total, MAX_PART_MINUTES)
    parts = []
    remaining = total
    index = 0
    while remaining > 0:
        minutes = min(chunk, remaining)
        part_count_guess = -(-total // chunk)
        label = title if part_count_guess == 1 else f"{title} (part {index + 1})"
        parts.append({"index": index, "title": label, "minutes": minutes})
        remaining -= minutes
        index += 1
    return parts


class RecommendationService:
    def __init__(self, db: Session, user_id: uuid.UUID) -> None:
        self.db = db
        self.user_id = user_id

    def _preference(self) -> UserPreference:
        preference = self.db.scalar(
            select(UserPreference).where(UserPreference.user_id == self.user_id)
        )
        if preference is None:
            preference = UserPreference(user_id=self.user_id)
            self.db.add(preference)
            self.db.flush()
        return preference

    def _active_tasks(self) -> list[Task]:
        return list(
            self.db.scalars(
                select(Task).where(
                    Task.user_id == self.user_id,
                    Task.is_archived.is_(False),
                    Task.status != TaskStatus.completed,
                )
            ).all()
        )

    @staticmethod
    def _sort_tasks(tasks: list[Task], now: datetime) -> list[Task]:
        return sorted(
            tasks,
            key=lambda t: (
                t.deadline is not None and t.deadline < now,  # overdue first
                t.deadline or now + timedelta(days=3650),  # soonest deadline
                PRIORITY_WEIGHT.get(t.priority, 1),
            ),
        )

    @staticmethod
    def _reason(task: Task, part_index: int, part_count: int, tz: ZoneInfo) -> str:
        reasons: list[str] = []
        if task.deadline is not None:
            local_deadline = task.deadline.astimezone(tz)
            if task.deadline < _utc_now():
                reasons.append("Overdue")
            else:
                days_left = (local_deadline.date() - datetime.now(tz).date()).days
                if days_left <= 0:
                    reasons.append("Due today")
                elif days_left == 1:
                    reasons.append("Due tomorrow")
                else:
                    reasons.append(f"Due in {days_left} days")
        if task.priority == TaskPriority.high:
            reasons.append("high priority")
        elif task.priority == TaskPriority.low:
            reasons.append("low priority")
        if part_count > 1:
            reasons.append(f"part {part_index + 1} of {part_count}")
        return ", ".join(reasons) if reasons else "fits your free time"

    def daily_recommendations(
        self,
        *,
        timezone_name: str,
        start_date: date | None,
        end_date: date | None,
        busy_times: list[BusyTime],
    ) -> dict:
        tz = ZoneInfo(timezone_name)
        now = _utc_now()
        today = now.astimezone(tz).date()

        window_start = start_date or today
        window_end = end_date or (window_start + timedelta(days=6))
        if window_end < window_start:
            window_end = window_start

        dates = [
            window_start + timedelta(days=offset)
            for offset in range((window_end - window_start).days + 1)
        ]

        preference = self._preference()
        tasks = self._sort_tasks(self._active_tasks(), now)

        free_slots = find_free_slots(
            dates=dates,
            busy=[
                TimeSlot(busy.start, busy.end)
                for busy in busy_times
                if not busy.start.astimezone(tz).date() > window_end
            ],
            start_hour=preference.work_hours_start,
            end_hour=preference.work_hours_end,
            timezone=timezone_name,
        )
        slots_by_day: dict[date, list[TimeSlot]] = {}
        for slot in free_slots:
            slots_by_day.setdefault(slot.start.astimezone(tz).date(), []).append(slot)

        pending: list[tuple[Task, dict, int]] = []  # (task, part, part_count)
        for task in tasks:
            duration = task.estimated_duration or 30
            parts = split_task_into_parts(task.title, task.description, duration)
            for part in parts:
                pending.append((task, part, len(parts)))

        days: list[dict] = []
        day_cursor = 0
        unscheduled: list[dict] = []

        for day in dates:
            day_slots = slots_by_day.get(day, [])
            capacity = sum(slot.duration_minutes for slot in day_slots)
            items: list[dict] = []

            while pending and capacity > 0:
                task, part, part_count = pending[0]
                minutes = part["minutes"]
                if minutes <= capacity:
                    items.append(
                        {
                            "task_id": str(task.id),
                            "task_title": task.title,
                            "part_title": part["title"],
                            "part_index": part["index"],
                            "part_count": part_count,
                            "minutes": minutes,
                            "priority": task.priority.value,
                            "deadline": (
                                task.deadline.isoformat() if task.deadline else None
                            ),
                            "is_overdue": (
                                task.deadline is not None and task.deadline < now
                            ),
                            "reason": self._reason(task, part["index"], part_count, tz),
                        }
                    )
                    capacity -= minutes
                    pending.pop(0)
                else:
                    break

            days.append(
                {
                    "date": day.isoformat(),
                    "available_minutes": sum(
                        slot.duration_minutes for slot in day_slots
                    ),
                    "items": items,
                }
            )

        for task, part, part_count in pending:
            unscheduled.append(
                {
                    "task_id": str(task.id),
                    "task_title": task.title,
                    "part_title": part["title"],
                    "minutes": part["minutes"],
                    "priority": task.priority.value,
                }
            )

        return {"days": days, "unscheduled": unscheduled}

    def breakdown_task(self, task: Task) -> dict:
        duration = task.estimated_duration or 30
        parts = split_task_into_parts(task.title, task.description, duration)
        return {
            "task_id": str(task.id),
            "task_title": task.title,
            "parts": parts,
            "source": "description" if len(parts) > 1 and task.description else "chunked",
        }
