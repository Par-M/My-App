import uuid
from datetime import datetime

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field
from pydantic import field_validator

from app.models.task import TaskPriority
from app.models.task import TaskStatus
from app.schemas.calendar import CalendarBlockResponse


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    deadline: datetime | None = None
    priority: TaskPriority = TaskPriority.medium
    status: TaskStatus = TaskStatus.pending
    estimated_duration: int | None = Field(default=None, ge=1, le=525600)
    actual_duration: int | None = Field(default=None, ge=0, le=525600)
    category: str | None = Field(default=None, max_length=100)
    notes: str | None = None

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("title must not be blank")
        return value.strip()


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    deadline: datetime | None = None
    priority: TaskPriority | None = None
    status: TaskStatus | None = None
    estimated_duration: int | None = Field(default=None, ge=1, le=525600)
    actual_duration: int | None = Field(default=None, ge=0, le=525600)
    category: str | None = Field(default=None, max_length=100)
    notes: str | None = None

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("title must not be blank")
        return value.strip() if value is not None else None


class TaskResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    title: str
    description: str | None
    deadline: datetime | None
    priority: TaskPriority
    status: TaskStatus
    estimated_duration: int | None
    actual_duration: int | None
    started_at: datetime | None
    completed_at: datetime | None
    category: str | None
    notes: str | None
    is_archived: bool
    created_at: datetime
    updated_at: datetime


class TaskListResponse(BaseModel):
    items: list[TaskResponse]
    total: int


class CompleteTaskRequest(BaseModel):
    actual_minutes: int | None = Field(default=None, ge=1, le=525600)


class SnoozeRequest(BaseModel):
    minutes: int = Field(ge=1, le=1440)
    timezone: str = "UTC"


class SnoozeResponse(BaseModel):
    task: TaskResponse
    blocks: list[CalendarBlockResponse]
