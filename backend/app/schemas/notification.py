import uuid
from datetime import datetime
from datetime import time as dt_time

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field


class DeviceRegisterRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    token: str = Field(min_length=1, max_length=512)
    platform: str = Field(default="ios", max_length=32)
    timezone: str = Field(default="UTC", max_length=64)


class DeviceTokenResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    device_id: str
    token: str
    platform: str
    timezone: str
    is_active: bool
    created_at: datetime
    updated_at: datetime


class NotificationPreferenceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    morning_briefing_enabled: bool
    morning_briefing_time: dt_time
    deadline_reminder_enabled: bool
    deadline_reminder_lead_hours: int
    overdue_alerts_enabled: bool
    fifteen_minute_reminder_enabled: bool
    fifteen_minute_reminder_lead_minutes: int
    reschedule_alerts_enabled: bool


class NotificationPreferenceUpdate(BaseModel):
    morning_briefing_enabled: bool | None = None
    morning_briefing_time: dt_time | None = None
    deadline_reminder_enabled: bool | None = None
    deadline_reminder_lead_hours: int | None = Field(default=None, ge=1, le=168)
    overdue_alerts_enabled: bool | None = None
    fifteen_minute_reminder_enabled: bool | None = None
    fifteen_minute_reminder_lead_minutes: int | None = Field(
        default=None, ge=1, le=120
    )
    reschedule_alerts_enabled: bool | None = None
