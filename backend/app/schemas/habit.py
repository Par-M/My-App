import uuid
from datetime import date as dt_date
from datetime import datetime

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field
from pydantic import field_validator


def _normalize_weekdays(value: list[int] | None) -> list[int] | None:
    """Validate weekday numbers (0=Sunday..6=Saturday) and dedupe them."""
    if not value:
        return None
    if any(day < 0 or day > 6 for day in value):
        raise ValueError(
            "weekdays must be integers between 0 (Sunday) and 6 (Saturday)"
        )
    return sorted(set(value))


class HabitCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    repeat_weekdays: list[int] | None = None
    daily_goal: int = Field(default=1, ge=1, le=100)

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


class HabitUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    repeat_weekdays: list[int] | None = None
    daily_goal: int | None = Field(default=None, ge=1, le=100)

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


class HabitResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    title: str
    repeat_weekdays: list[int] | None
    daily_goal: int
    created_at: datetime
    updated_at: datetime


class HabitListResponse(BaseModel):
    items: list[HabitResponse]
    total: int


class HabitLogCreate(BaseModel):
    count: int = Field(default=1, ge=1, le=1000)
    date: dt_date | None = None


class HabitLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    habit_id: uuid.UUID
    count: int
    completed_at: datetime
    created_at: datetime


class HabitDaySet(BaseModel):
    count: int = Field(ge=0, le=1000)
    date: dt_date | None = None


class HabitDaySetResponse(BaseModel):
    habit_id: uuid.UUID
    date: dt_date
    count: int


class HabitDayStats(BaseModel):
    date: dt_date
    scheduled: bool
    completed_count: int


class HabitStats(BaseModel):
    habit: HabitResponse
    current_streak: int
    best_streak: int
    completion_rate_7d: float
    completion_rate_30d: float
    scheduled_7d: int
    completed_7d: int
    total_completions: int
    last_7_days: list[HabitDayStats]


class HabitDashboardResponse(BaseModel):
    habits: list[HabitStats]
