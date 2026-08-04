from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field
from pydantic import model_validator


class UserPreferenceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    work_hours_start: int
    work_hours_end: int
    buffer_minutes: int
    energy_level: int


class UserPreferenceUpdate(BaseModel):
    work_hours_start: int | None = Field(default=None, ge=0, le=23)
    work_hours_end: int | None = Field(default=None, ge=0, le=24)
    buffer_minutes: int | None = Field(default=None, ge=0, le=120)
    energy_level: int | None = Field(default=None, ge=1, le=5)

    @model_validator(mode="after")
    def validate_work_hours(self):
        start = self.work_hours_start
        end = self.work_hours_end
        if start is not None and end is not None and end <= start:
            raise ValueError("work_hours_end must be after work_hours_start")
        return self
