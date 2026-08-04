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


def build_prompt(context: SchedulingContext) -> str:
    lines = [
        "You are an expert scheduling assistant. Build a realistic schedule for the user's tasks.",
        "",
        f"Scheduling window: {context.dates[0].isoformat()} to {context.dates[-1].isoformat()} (local timezone {context.timezone}).",
        f"Working hours: {context.work_start_hour}:00-{context.work_end_hour}:00 local time.",
        f"Buffer between blocks: {context.buffer_minutes} minutes. Do not overlap blocks or busy times.",
        f"User energy level (1-5): {context.energy_level}. Schedule demanding work during the user's most energetic window.",
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
        "another block or a busy slot. If a task cannot fit, omit it and say so in "
        "reasoning."
    )
    return "\n".join(lines)
