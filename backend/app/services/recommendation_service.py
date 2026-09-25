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
                    # Tasks with an explicit start time are already placed
                    # (fixed events); never re-recommend them.
                    Task.start_at.is_(None),
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

    @staticmethod
    def _allocate_window(
        slots: list[TimeSlot],
        used_by_slot: list[int],
        minutes: int,
    ) -> tuple[datetime | None, datetime | None]:
        """Assign a concrete start/end window for a recommended part by filling
        the day's free slots in chronological order."""
        remaining = minutes
        start: datetime | None = None
        end: datetime | None = None

        for index, slot in enumerate(slots):
            slot_free = slot.duration_minutes - used_by_slot[index]
            if slot_free <= 0:
                continue
            cursor = slot.start + timedelta(minutes=used_by_slot[index])
            take = min(remaining, slot_free)
            if start is None:
                start = cursor
            end = cursor + timedelta(minutes=take)
            used_by_slot[index] += take
            remaining -= take
            if remaining <= 0:
                break

        return start, end

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
            # "Amount left" = estimated duration minus time already completed
            # (recorded via the task's actual_duration). Tasks with nothing left
            # are fully done and are not recommended again.
            estimated = task.estimated_duration or 30
            completed = task.actual_duration or 0
            amount_left = max(0, estimated - completed)
            if amount_left <= 0:
                continue
            parts = split_task_into_parts(task.title, task.description, amount_left)
            for part in parts:
                pending.append((task, part, len(parts)))

        slots_by_date: dict[date, list[TimeSlot]] = {
            day: sorted(
                slots_by_day.get(day, []),
                key=lambda slot: (slot.start, slot.end),
            )
            for day in dates
        }
        capacity_by_date: dict[date, int] = {
            day: sum(slot.duration_minutes for slot in slots_by_date[day])
            for day in dates
        }
        used_by_slot: dict[date, list[int]] = {
            day: [0] * len(slots_by_date[day]) for day in dates
        }
        items_by_date: dict[date, list[dict]] = {day: [] for day in dates}
        used_by_date: dict[date, int] = {day: 0 for day in dates}

        days: list[dict] = []
        unscheduled: list[dict] = []
        # Parts of the same task must appear in order: once a part is placed on
        # a day, later parts are only allowed on that same day or later, so part
        # 9 never shows a time block before parts 1-8. If an earlier part cannot
        # be placed anywhere, the remaining parts are not recommended either.
        last_day_by_task: dict[str, int] = {}
        blocked_task: set[str] = set()

        def unscheduled_item(task: Task, part: dict) -> dict:
            return {
                "task_id": str(task.id),
                "task_title": task.title,
                "part_title": part["title"],
                "part_index": part["index"],
                "minutes": part["minutes"],
                "priority": task.priority.value,
            }

        for task, part, part_count in pending:
            minutes = part["minutes"]
            task_id = str(task.id)
            if task_id in blocked_task:
                unscheduled.append(unscheduled_item(task, part))
                continue

            # Eligible days = where the part can still be placed without missing
            # the deadline: from today through (and including) the deadline day.
            # Tasks with no deadline (or a deadline outside the window) can go
            # anywhere in the window; overdue work is kept to the earliest days.
            eligible = self._eligible_days(task, dates, tz, window_start, window_end)

            # Keep parts in sequence: only allow days on/after the previous
            # part's day so the plan reads part 1, 2, 3, ... chronologically.
            floor = last_day_by_task.get(task_id, 0)
            eligible = [i for i in eligible if i >= floor]

            # Pick the eligible day that is least loaded so far (relative to its
            # total free capacity), so work is spread across the available time
            # before the deadline instead of piling everything into the earliest
            # free day. Ties break toward the earliest day so nearer-deadline
            # work is nudged to the front.
            def load(day_index: int) -> float:
                day = dates[day_index]
                capacity = capacity_by_date[day]
                return used_by_date[day] / capacity if capacity > 0 else 1.0

            candidates = [
                i
                for i in eligible
                if capacity_by_date[dates[i]] - used_by_date[dates[i]] >= minutes
            ]

            if not candidates:
                blocked_task.add(task_id)
                unscheduled.append(unscheduled_item(task, part))
                continue

            best_index = min(candidates, key=lambda i: (load(i), i))
            day = dates[best_index]
            day_slots = slots_by_date[day]
            block_start, block_end = self._allocate_window(
                day_slots, used_by_slot[day], minutes
            )
            if block_start is None:
                blocked_task.add(task_id)
                unscheduled.append(unscheduled_item(task, part))
                continue

            used_by_date[day] += minutes
            last_day_by_task[task_id] = best_index
            items_by_date[day].append(
                {
                    "task_id": str(task.id),
                    "task_title": task.title,
                    "part_title": part["title"],
                    "part_index": part["index"],
                    "part_count": part_count,
                    "minutes": minutes,
                    "priority": task.priority.value,
                    "category": task.category,
                    "deadline": (
                        task.deadline.isoformat() if task.deadline else None
                    ),
                    "is_overdue": (
                        task.deadline is not None and task.deadline < now
                    ),
                    "reason": self._reason(task, part["index"], part_count, tz),
                    "start_at": (
                        block_start.isoformat() if block_start else None
                    ),
                    "end_at": (
                        block_end.isoformat() if block_end else None
                    ),
                }
            )

        # Stable chained sort within each day: overdue first, then soonest
        # deadline, then highest priority, then part order, so items read most-
        # urgent first and multi-part tasks appear in sequence.
        priority_string_weight = {
            "high": PRIORITY_WEIGHT[TaskPriority.high],
            "medium": PRIORITY_WEIGHT[TaskPriority.medium],
            "low": PRIORITY_WEIGHT[TaskPriority.low],
        }
        for day in dates:
            items_by_date[day].sort(
                key=lambda item: (
                    not item["is_overdue"],
                    item["deadline"] or "9999",
                    priority_string_weight.get(item.get("priority"), 1),
                    item["part_index"],
                )
            )
            days.append(
                {
                    "date": day.isoformat(),
                    "available_minutes": capacity_by_date[day],
                    "items": items_by_date[day],
                }
            )

        return {"days": days, "unscheduled": unscheduled}

    @staticmethod
    def _eligible_days(
        task: Task,
        dates: list[date],
        tz,
        window_start: date,
        window_end: date,
    ) -> list[int]:
        """Day indices a part may be placed on while still finishing before the
        deadline. Overdue work is restricted to the earliest days so it is
        prioritized; otherwise the window runs from today through the deadline
        (or the whole window when there is no deadline)."""
        last = len(dates) - 1
        if task.deadline is None:
            return list(range(last + 1))
        deadline_day = task.deadline.astimezone(tz).date()
        if deadline_day < window_start:
            return list(range(min(2, last + 1)))
        for index, day in enumerate(dates):
            if day > deadline_day:
                return list(range(index)) or [0]
        return list(range(last + 1))

    def breakdown_task(self, task: Task) -> dict:
        duration = task.estimated_duration or 30
        parts = split_task_into_parts(task.title, task.description, duration)
        return {
            "task_id": str(task.id),
            "task_title": task.title,
            "parts": parts,
            "source": "description" if len(parts) > 1 and task.description else "chunked",
        }
