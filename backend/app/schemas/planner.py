import uuid
from datetime import date
from datetime import datetime

from pydantic import BaseModel
from pydantic import ConfigDict

from app.schemas.calendar import CalendarBlockResponse
from app.schemas.task import TaskResponse


class ScheduledTask(TaskResponse):
    start: datetime | None = None
    end: datetime | None = None


class TodayResponse(BaseModel):
    current_task: ScheduledTask | None = None
    priority_task: ScheduledTask | None = None
    next_tasks: list[ScheduledTask] = []
    completed_today: int = 0
    focus_time_remaining: int = 0
    day_progress: float = 0.0


class MissedTaskEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    task_id: uuid.UUID
    task_title: str
    category: str | None
    missed_deadline: datetime | None
    reason: str | None
    minutes_remaining: int | None
    rescheduled_to: datetime | None
    created_at: datetime


class DailySummaryResponse(BaseModel):
    date: date
    completed: list[TaskResponse] = []
    in_progress: list[TaskResponse] = []
    pending: list[TaskResponse] = []
    hours_worked: float = 0.0
    tasks_remaining: int = 0
    tasks_moved: int = 0
    schedule_adherence: float = 1.0
    missed_today: list[MissedTaskEntry] = []


class CategoryMissed(BaseModel):
    category: str
    count: int
    reasons: list[MissedTaskEntry] = []


class MissedReasonsResponse(BaseModel):
    total: int = 0
    by_category: list[CategoryMissed] = []
