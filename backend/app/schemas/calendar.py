import uuid
from datetime import datetime

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field
from pydantic import field_validator


class BusyTime(BaseModel):
    start: datetime
    end: datetime

    @field_validator("end")
    @classmethod
    def end_after_start(cls, value: datetime, info) -> datetime:
        start = info.data.get("start")
        if start is not None and value <= start:
            raise ValueError("end must be after start")
        return value


class TimeSlot(BaseModel):
    start: datetime
    end: datetime


class CalendarBlockCreate(BaseModel):
    task_id: uuid.UUID
    title: str = Field(min_length=1, max_length=255)
    start_at: datetime
    end_at: datetime
    calendar_event_id: str | None = Field(default=None, max_length=255)

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("title must not be blank")
        return value.strip()


class CalendarBlockUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    start_at: datetime | None = None
    end_at: datetime | None = None
    calendar_event_id: str | None = Field(default=None, max_length=255)


class CompleteBlockRequest(BaseModel):
    note: str | None = Field(default=None, max_length=2000)


class CalendarBlockResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    task_id: uuid.UUID
    calendar_event_id: str | None
    title: str
    start_at: datetime
    end_at: datetime
    completed_at: datetime | None
    completion_note: str | None
    created_at: datetime
    updated_at: datetime


class CalendarBlockListResponse(BaseModel):
    items: list[CalendarBlockResponse]
    total: int
