from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from app.services.scheduling.context import TimeSlot

MIN_FREE_SLOT = timedelta(minutes=15)


def _as_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=ZoneInfo("UTC"))
    return value


def _normalize_slot(interval) -> TimeSlot:
    start = _as_aware(interval.start)
    end = _as_aware(interval.end)
    return TimeSlot(start, end)


def merge_intervals(intervals: list[TimeSlot]) -> list[TimeSlot]:
    ordered = sorted(
        (_normalize_slot(interval) for interval in intervals),
        key=lambda slot: (slot.start, slot.end),
    )
    merged: list[TimeSlot] = []
    for slot in ordered:
        if slot.start >= slot.end:
            continue
        if merged and slot.start <= merged[-1].end:
            if slot.end > merged[-1].end:
                merged[-1] = TimeSlot(merged[-1].start, slot.end)
        else:
            merged.append(slot)
    return merged


def _hour_minute(value: float) -> tuple[int, int]:
    hour = int(value)
    minute = int(round((value - hour) * 60))
    if minute == 60:
        hour += 1
        minute = 0
    return hour, minute


def working_windows(
    dates: list[date],
    *,
    start_hour: float,
    end_hour: float,
    timezone: str,
) -> list[TimeSlot]:
    tz = ZoneInfo(timezone)
    start_h, start_m = _hour_minute(start_hour)
    end_h, end_m = _hour_minute(end_hour)
    windows: list[TimeSlot] = []
    for day in dates:
        start = datetime.combine(day, time(start_h, start_m), tzinfo=tz)
        end = datetime.combine(day, time(end_h, end_m), tzinfo=tz)
        if end <= start:
            continue
        windows.append(TimeSlot(start, end))
    return windows


def find_free_slots(
    *,
    dates: list[date],
    busy: list[TimeSlot],
    start_hour: float,
    end_hour: float,
    timezone: str,
    min_duration: timedelta = MIN_FREE_SLOT,
) -> list[TimeSlot]:
    """Compute free time inside working hours, excluding busy intervals."""
    merged = merge_intervals(busy)
    slots: list[TimeSlot] = []
    for window in working_windows(
        dates, start_hour=start_hour, end_hour=end_hour, timezone=timezone
    ):
        cursor = window.start
        for busy_slot in merged:
            if busy_slot.end <= window.start or busy_slot.start >= window.end:
                continue
            busy_start = max(busy_slot.start, window.start)
            busy_end = min(busy_slot.end, window.end)
            if busy_start > cursor:
                gap = busy_start - cursor
                if gap >= min_duration:
                    slots.append(TimeSlot(cursor, busy_start))
            cursor = max(cursor, busy_end)
        if window.end > cursor and (window.end - cursor) >= min_duration:
            slots.append(TimeSlot(cursor, window.end))
    return slots
