import uuid
from datetime import date
from datetime import datetime
from datetime import timedelta
from datetime import time as dt_time
from datetime import timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.habit import Habit
from app.models.habit import HabitLog
from app.repositories import habit_repository
from app.schemas.habit import HabitCreate
from app.schemas.habit import HabitDayStats
from app.schemas.habit import HabitStats
from app.schemas.habit import HabitUpdate


class HabitNotFoundError(Exception):
    pass


def _app_weekday(day: date) -> int:
    """Map a date to the app's weekday convention (0=Sunday..6=Saturday)."""
    return (day.weekday() + 1) % 7


def _is_scheduled(habit: Habit, day: date) -> bool:
    weekdays = habit.repeat_weekdays
    return weekdays is None or _app_weekday(day) in weekdays


def _streaks(
    days: list[date],
    totals: dict[date, int],
    daily_goal: int,
    scheduled: callable,
) -> tuple[int, int]:
    best = 0
    run = 0
    for day in days:
        if not scheduled(day):
            continue
        if totals.get(day, 0) >= daily_goal:
            run += 1
            best = max(best, run)
        else:
            run = 0

    current = 0
    for day in reversed(days):
        if not scheduled(day):
            continue
        if totals.get(day, 0) >= daily_goal:
            current += 1
        else:
            break
    return current, best


def _window_rate(
    scheduled_days: list[date],
    totals: dict[date, int],
    daily_goal: int,
    start: date,
) -> tuple[float, int, int]:
    window = [d for d in scheduled_days if d >= start]
    if not window:
        return 1.0, 0, 0
    done = sum(1 for d in window if totals.get(d, 0) >= daily_goal)
    return round(done / len(window), 2), len(window), done


class HabitService:
    def __init__(self, db: Session, user_id: uuid.UUID):
        self.db = db
        self.user_id = user_id

    def _get(self, habit_id: uuid.UUID) -> Habit:
        habit = habit_repository.get_habit(
            self.db, user_id=self.user_id, habit_id=habit_id
        )
        if habit is None:
            raise HabitNotFoundError("Habit not found")
        return habit

    def create_habit(self, data: HabitCreate) -> Habit:
        habit = habit_repository.create_habit(
            self.db, user_id=self.user_id, data=data
        )
        self.db.commit()
        self.db.refresh(habit)
        return habit

    def list_habits(self) -> list[Habit]:
        return habit_repository.list_habits(self.db, user_id=self.user_id)

    def update_habit(self, habit_id: uuid.UUID, data: HabitUpdate) -> Habit:
        habit = self._get(habit_id)
        habit = habit_repository.update_habit(self.db, habit, data)
        self.db.commit()
        self.db.refresh(habit)
        return habit

    def delete_habit(self, habit_id: uuid.UUID) -> None:
        habit = self._get(habit_id)
        habit_repository.delete_habit(self.db, habit)
        self.db.commit()

    def log_completion(
        self,
        habit_id: uuid.UUID,
        count: int,
        on_date: date | None = None,
    ) -> HabitLog:
        habit = self._get(habit_id)
        if on_date is not None:
            completed_at = datetime.combine(
                on_date, dt_time.min, tzinfo=timezone.utc
            )
        else:
            completed_at = datetime.now(timezone.utc)
        log = habit_repository.add_log(
            self.db,
            user_id=self.user_id,
            habit_id=habit.id,
            count=count,
            completed_at=completed_at,
        )
        self.db.commit()
        self.db.refresh(log)
        return log

    def set_day_count(
        self,
        habit_id: uuid.UUID,
        count: int,
        on_date: date | None = None,
        timezone_name: str = "UTC",
    ) -> tuple[date, int]:
        habit = self._get(habit_id)
        tz = ZoneInfo(timezone_name)
        day = on_date if on_date is not None else datetime.now(tz).date()
        day_start = datetime.combine(day, dt_time.min, tzinfo=tz).astimezone(timezone.utc)
        day_end = day_start + timedelta(days=1)

        existing = self.db.scalars(
            select(HabitLog).where(
                HabitLog.habit_id == habit.id,
                HabitLog.completed_at >= day_start,
                HabitLog.completed_at < day_end,
            )
        ).all()
        for log in existing:
            self.db.delete(log)

        if count > 0:
            habit_repository.add_log(
                self.db,
                user_id=self.user_id,
                habit_id=habit.id,
                count=count,
                completed_at=day_start,
            )
        self.db.commit()
        return day, count

    def dashboard(self, timezone_name: str = "UTC") -> list[HabitStats]:
        tz = ZoneInfo(timezone_name)
        today = datetime.now(tz).date()
        habits = self.list_habits()

        stats: list[HabitStats] = []
        for habit in habits:
            logs = list(
                self.db.scalars(
                    select(HabitLog).where(HabitLog.habit_id == habit.id)
                ).all()
            )
            totals: dict[date, int] = {}
            for log in logs:
                day = log.completed_at.astimezone(tz).date()
                totals[day] = totals.get(day, 0) + (log.count or 0)

            created_date = habit.created_at.astimezone(tz).date()
            first_day = min(created_date, today)
            days = [
                first_day + timedelta(days=offset)
                for offset in range((today - first_day).days + 1)
            ]
            scheduled_days = [d for d in days if _is_scheduled(habit, d)]

            current_streak, best_streak = _streaks(
                days, totals, habit.daily_goal, lambda d: _is_scheduled(habit, d)
            )

            rate_7d, scheduled_7d, completed_7d = _window_rate(
                scheduled_days,
                totals,
                habit.daily_goal,
                today - timedelta(days=6),
            )
            rate_30d, _, _ = _window_rate(
                scheduled_days,
                totals,
                habit.daily_goal,
                today - timedelta(days=29),
            )

            last_7_days = [
                HabitDayStats(
                    date=day,
                    scheduled=_is_scheduled(habit, day),
                    completed_count=totals.get(day, 0),
                )
                for day in (today - timedelta(days=offset) for offset in range(6, -1, -1))
            ]

            stats.append(
                HabitStats(
                    habit=habit,
                    current_streak=current_streak,
                    best_streak=best_streak,
                    completion_rate_7d=rate_7d,
                    completion_rate_30d=rate_30d,
                    scheduled_7d=scheduled_7d,
                    completed_7d=completed_7d,
                    total_completions=sum(totals.values()),
                    last_7_days=last_7_days,
                )
            )

        stats.sort(
            key=lambda s: (
                s.completion_rate_30d,
                s.current_streak,
                s.habit.created_at,
            ),
            reverse=True,
        )
        return stats
