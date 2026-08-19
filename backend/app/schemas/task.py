import uuid
from datetime import datetime

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field
from pydantic import field_validator
from pydantic import model_validator

from app.models.task import TaskPriority
from app.models.task import TaskProductivity
from app.models.task import TaskStatus
from app.schemas.calendar import CalendarBlockResponse


def _normalize_weekdays(value: list[int] | None) -> list[int] | None:
    """Validate weekday numbers (0=Sunday..6=Saturday) and dedupe them."""
    if not value:
        return None
    if any(day < 0 or day > 6 for day in value):
        raise ValueError(
            "weekdays must be integers between 0 (Sunday) and 6 (Saturday)"
        )
    return sorted(set(value))


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    deadline: datetime | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    priority: TaskPriority = TaskPriority.medium
    status: TaskStatus = TaskStatus.pending
    estimated_duration: int | None = Field(default=None, ge=1, le=525600)
    actual_duration: int | None = Field(default=None, ge=0, le=525600)
    productivity: TaskProductivity | None = None
    category: str | None = Field(default=None, max_length=100)
    notes: str | None = None
    repeat_weekdays: list[int] | None = None
    before_task_ids: list[uuid.UUID] | None = None
    after_task_ids: list[uuid.UUID] | None = None

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("title must not be blank")
        return value.strip()

    @field_validator("repeat_weekdays")
    @classmethod
    def repeat_weekdays_valid(cls, value: list[int] | None) -> list[int] | None:
        return _normalize_weekdays(value)

    @model_validator(mode="after")
    def fixed_event_times_valid(self):
        if self.start_at is None and self.end_at is None:
            return self
        if self.start_at is None or self.end_at is None:
            raise ValueError("start_at and end_at must be set together")
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        return self


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    deadline: datetime | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    priority: TaskPriority | None = None
    status: TaskStatus | None = None
    estimated_duration: int | None = Field(default=None, ge=1, le=525600)
    actual_duration: int | None = Field(default=None, ge=0, le=525600)
    productivity: TaskProductivity | None = None
    category: str | None = Field(default=None, max_length=100)
    notes: str | None = None
    repeat_weekdays: list[int] | None = None
    before_task_ids: list[uuid.UUID] | None = None
    after_task_ids: list[uuid.UUID] | None = None

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("title must not be blank")
        return value.strip() if value is not None else None

    @field_validator("repeat_weekdays")
    @classmethod
    def repeat_weekdays_valid(cls, value: list[int] | None) -> list[int] | None:
        return _normalize_weekdays(value)

    @field_validator("before_task_ids")
    @classmethod
    def before_ids_valid(cls, value: list[uuid.UUID] | None) -> list[uuid.UUID] | None:
        return list(dict.fromkeys(value)) if value else None

    @field_validator("after_task_ids")
    @classmethod
    def after_ids_valid(cls, value: list[uuid.UUID] | None) -> list[uuid.UUID] | None:
        return list(dict.fromkeys(value)) if value else None

    @model_validator(mode="after")
    def fixed_event_times_valid(self):
        if self.start_at is not None and self.end_at is not None:
            if self.end_at <= self.start_at:
                raise ValueError("end_at must be after start_at")
        return self


class TaskResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    title: str
    description: str | None
    deadline: datetime | None
    start_at: datetime | None
    end_at: datetime | None
    priority: TaskPriority
    status: TaskStatus
    estimated_duration: int | None
    actual_duration: int | None
    productivity: TaskProductivity | None
    started_at: datetime | None
    completed_at: datetime | None
    category: str | None
    notes: str | None
    progress_percent: int
    repeat_weekdays: list[int] | None
    before_task_ids: list[uuid.UUID] | None
    after_task_ids: list[uuid.UUID] | None
    is_archived: bool
    created_at: datetime
    updated_at: datetime


class TaskListResponse(BaseModel):
    items: list[TaskResponse]
    total: int


class CompleteTaskRequest(BaseModel):
    actual_minutes: int | None = Field(default=None, ge=1, le=525600)
    productivity: TaskProductivity | None = None


class SnoozeRequest(BaseModel):
    minutes: int = Field(ge=1, le=1440)
    timezone: str = "UTC"


class SnoozeResponse(BaseModel):
    task: TaskResponse
    blocks: list[CalendarBlockResponse]


class RescheduleRequest(BaseModel):
    minutes_remaining: int = Field(ge=1, le=525600)
    reason: str | None = Field(default=None, max_length=2000)
    timezone: str = "UTC"


class RescheduleResponse(BaseModel):
    task: TaskResponse
    blocks: list[CalendarBlockResponse]
