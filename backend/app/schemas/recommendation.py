import uuid
from datetime import date
from datetime import datetime

from pydantic import BaseModel
from pydantic import Field

from app.models.task import TaskPriority
from app.schemas.calendar import BusyTime


class DailyRecommendationsRequest(BaseModel):
    timezone: str = "UTC"
    start_date: date | None = None
    end_date: date | None = None
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
