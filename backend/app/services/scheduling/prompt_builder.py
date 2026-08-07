from datetime import date

from app.services.scheduling.context import SchedulingContext
from app.services.scheduling.context import TaskContext
from app.services.scheduling.context import TimeSlot


def _local(ts: TimeSlot, timezone: str) -> str:
    start = ts.start.astimezone(_tz(timezone))
    end = ts.end.astimezone(_tz(timezone))
    return f"{start.strftime('%a %H:%M')}-{end.strftime('%H:%M')} ({start.date().isoformat()})"


def _tz(timezone: str):
    from zoneinfo import ZoneInfo

    return ZoneInfo(timezone)


def _deadline(task: TaskContext) -> str:
    if task.deadline is None:
        return "none"
    return task.deadline.date().isoformat()


def _hour_text(value: float) -> str:
    hour = int(value)
    minute = int(round((value - hour) * 60))
    if minute == 60:
        hour += 1
        minute = 0
    return f"{hour}:{minute:02d}"


def build_prompt(context: SchedulingContext) -> str:
    lines = [
        "You are an expert scheduling assistant. Build a realistic schedule for the user's tasks.",
        "",
        f"Scheduling window: {context.dates[0].isoformat()} to {context.dates[-1].isoformat()} (local timezone {context.timezone}).",
        f"Working hours: {_hour_text(context.work_start_hour)}-{_hour_text(context.work_end_hour)} local time.",
        f"Buffer between blocks: {context.buffer_minutes} minutes. Do not overlap blocks or busy times.",
        f"User energy level (1-5): {context.energy_level}. Schedule demanding work during the user's most energetic window.",
        f"Tasks longer than {context.max_chunk_minutes} minutes must be split into multiple blocks, "
        f"each at most {context.max_chunk_minutes} minutes and within a single free slot. "
        "All blocks of a task keep the same task_id; the blocks of one task together must cover its full duration.",
        "",
        "Tasks:",
    ]
    for task in context.tasks:
        lines.append(
            f"- id={task.id} | {task.title} | {task.duration_minutes} min "
            f"| priority={task.priority.value} | deadline={_deadline(task)} "
            f"| energy={task.energy_level}"
        )
    lines.append("")
    lines.append("Free time slots (UTC ISO times are given in the schedule):")
    if context.free_slots:
        for slot in context.free_slots:
            lines.append(
                f"- {_local(slot, context.timezone)} "
                f"(UTC {slot.start.isoformat()} to {slot.end.isoformat()})"
            )
    else:
        lines.append("- (none available)")
    lines.append("")
    lines.append(
        "Return ONLY a JSON object with this exact shape (no markdown):"
    )
    lines.append(
        """
{
  "items": [
    {
      "task_id": "<uuid>",
      "task_title": "<title>",
      "start": "<ISO8601 UTC start>",
      "end": "<ISO8601 UTC end>",
      "reason": "<human-readable reason>"
    }
  ],
  "reasoning": "<short overall explanation of the schedule choices>"
}
"""
    )
    lines.append(
        "Constraints: start must be >= end minus task duration; end must not exceed the "
        "task deadline; every block must be inside working hours and must not overlap "
        "another block or a busy slot. A task may appear as multiple blocks (its chunks); "
        "all of a task's blocks must fit before the deadline and together cover the full "
        "task duration. If a task cannot be fully scheduled, omit it entirely and say so "
        "in reasoning."
    )
    return "\n".join(lines)
