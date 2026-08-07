from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field
from pydantic import field_validator
from pydantic import model_validator


class UserPreferenceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    work_hours_start: float
    work_hours_end: float
    buffer_minutes: int
    energy_level: int
    max_daily_hours: int
    default_duration_minutes: int
    default_priority: str


def _validate_half_hour(value: float) -> float:
    if abs((value * 2) - round(value * 2)) > 1e-6:
        raise ValueError("Work hours must be in 30 minute increments")
    return float(round(value * 2) / 2)


class UserPreferenceUpdate(BaseModel):
    work_hours_start: float | None = Field(default=None, ge=0, le=24)
    work_hours_end: float | None = Field(default=None, ge=0, le=24)
    buffer_minutes: int | None = Field(default=None, ge=0, le=120)
    energy_level: int | None = Field(default=None, ge=1, le=5)
    max_daily_hours: int | None = Field(default=None, ge=1, le=16)
    default_duration_minutes: int | None = Field(default=None, ge=5, le=480)
    default_priority: str | None = Field(
        default=None, pattern="^(low|medium|high)$"
    )

    @field_validator("work_hours_start", "work_hours_end")
    @classmethod
    def half_hour_steps(cls, value: float | None) -> float | None:
        if value is None:
            return None
        return _validate_half_hour(value)

    @model_validator(mode="after")
    def validate_work_hours(self):
        start = self.work_hours_start
        end = self.work_hours_end
        if start is not None and end is not None and end <= start:
            raise ValueError("work_hours_end must be after work_hours_start")
        return self
