import uuid
from datetime import date
from datetime import datetime

from pydantic import BaseModel
from pydantic import Field

from app.models.task import TaskPriority
from app.schemas.calendar import BusyTime


class DailyRecommendationsRequest(BaseModel):
    timezone: str = "UTC"
    # Accepts full ISO datetimes (e.g. "2026-08-22T07:00:00Z" from iOS's
    # ISO8601 JSONEncoder) as well as plain "2026-08-22" dates.
    start_date: datetime | None = None
    end_date: datetime | None = None
    busy_times: list[BusyTime] = Field(default_factory=list)


class RecommendedPart(BaseModel):
    task_id: uuid.UUID
    task_title: str
    part_title: str | None
    part_index: int
    part_count: int
    minutes: int
    priority: TaskPriority
    deadline: datetime | None = None
    is_overdue: bool = False
    reason: str = ""
    # Concrete suggested time window (user-local ISO with offset).
    recommended_start: datetime | None = None
    recommended_end: datetime | None = None


class UnscheduledPart(BaseModel):
    task_id: uuid.UUID
    task_title: str
    part_title: str | None
    minutes: int
    priority: TaskPriority


class DayRecommendation(BaseModel):
    date: date
    available_minutes: int
    items: list[RecommendedPart]


class DailyRecommendationsResponse(BaseModel):
    days: list[DayRecommendation]
    unscheduled: list[UnscheduledPart]


class BreakdownPart(BaseModel):
    index: int
    title: str
    minutes: int


class BreakdownResponse(BaseModel):
    task_id: uuid.UUID
    task_title: str
    parts: list[BreakdownPart]
    source: str
