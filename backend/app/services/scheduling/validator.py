from dataclasses import dataclass
from dataclasses import field
from datetime import date
from datetime import datetime
from datetime import time
from datetime import timedelta
from zoneinfo import ZoneInfo

from app.services.scheduling.context import ProposedBlock
from app.services.scheduling.context import SchedulingContext


@dataclass
class ValidationResult:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def is_valid(self) -> bool:
        return not self.errors


def _normalize(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=ZoneInfo("UTC"))
    return value


def _hour_minute(value: float) -> tuple[int, int]:
    hour = int(value)
    minute = int(round((value - hour) * 60))
    if minute == 60:
        hour += 1
        minute = 0
    return hour, minute


def _window_for(block_start: datetime, context: SchedulingContext):
    tz = ZoneInfo(context.timezone)
    local = block_start.astimezone(tz)
    day = local.date()
    start_h, start_m = _hour_minute(context.work_start_hour)
    end_h, end_m = _hour_minute(context.work_end_hour)
    start = datetime.combine(day, time(start_h, start_m), tzinfo=tz)
    end = datetime.combine(day, time(end_h, end_m), tzinfo=tz)
    return start, end


def validate_schedule(
    result: ProposedBlock | list[ProposedBlock],
    context: SchedulingContext,
) -> ValidationResult:
    blocks = result if isinstance(result, list) else [result]
    validation = ValidationResult()

    tasks_by_id = {task.id: task for task in context.tasks}
    busy = [
        (_normalize(slot.start), _normalize(slot.end))
        for slot in context.busy_times
        if _normalize(slot.start) < _normalize(slot.end)
    ]

    seen_tasks: set[object] = set()
    normalized: list[tuple[ProposedBlock, datetime, datetime]] = []

    for block in blocks:
        start = _normalize(block.start)
        end = _normalize(block.end)

        if start >= end:
            validation.errors.append(
                f"Invalid time for '{block.task_title}': end is not after start"
            )
            continue
        if block.task_id not in tasks_by_id:
            validation.errors.append(
                f"Unknown task_id {block.task_id} in schedule output"
            )
            continue
        if block.task_id in seen_tasks:
            validation.errors.append(
                f"Task '{block.task_title}' is scheduled more than once"
            )
        seen_tasks.add(block.task_id)

        task = tasks_by_id[block.task_id]
        if task.deadline is not None and end > _normalize(task.deadline):
            validation.errors.append(
                f"Deadline violation for '{block.task_title}': "
                f"block ends after its deadline"
            )

        window_start, window_end = _window_for(start, context)
        if start < window_start or end > window_end:
            validation.errors.append(
                f"'{block.task_title}' is scheduled outside working hours"
            )

        for busy_start, busy_end in busy:
            if start < busy_end and end > busy_start:
                validation.errors.append(
                    f"'{block.task_title}' overlaps a busy calendar event"
                )
                break

        normalized.append((block, start, end))

    for index, (block, start, end) in enumerate(normalized):
        for _other_block, other_start, other_end in normalized[(index + 1) :]:
            if start < other_end and end > other_start:
                validation.errors.append(
                    f"'{block.task_title}' overlaps another scheduled block"
                )

    if context.buffer_minutes > 0:
        ordered = sorted(normalized, key=lambda entry: entry[1])
        for (first, f_start, f_end), (second, s_start, s_end) in zip(
            ordered, ordered[1:]
        ):
            gap = (s_start - f_end).total_seconds() / 60
            if 0 <= gap < context.buffer_minutes:
                validation.warnings.append(
                    f"Buffer of {context.buffer_minutes} minutes not kept between "
                    f"'{first.task_title}' and '{second.task_title}'"
                )

    scheduled_ids = {block.task_id for block, _, _ in normalized}
    for task in context.tasks:
        if task.id not in scheduled_ids:
            validation.warnings.append(
                f"Task '{task.title}' was not scheduled"
            )

    return validation
