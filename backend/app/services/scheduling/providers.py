import json
import math
from datetime import datetime
from datetime import timedelta
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

import httpx

from app.core.config import settings
from app.models.task import TaskPriority
from app.services.scheduling.context import ProposedBlock
from app.services.scheduling.context import ProviderResult
from app.services.scheduling.context import SchedulingContext
from app.services.scheduling.context import TimeSlot

PRIORITY_RANK = {
    TaskPriority.low: 0,
    TaskPriority.medium: 1,
    TaskPriority.high: 2,
}


class ProviderError(Exception):
    pass


class AIProvider(Protocol):
    def generate_schedule(
        self, context: SchedulingContext, prompt: str
    ) -> ProviderResult:
        """Return a proposed schedule for the given context."""
        ...


def default_provider() -> AIProvider:
    if settings.gemini_api_key:
        return GeminiProvider()
    return HeuristicProvider()


def _parse_datetime(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=ZoneInfo("UTC"))
    return parsed


class GeminiProvider:
    """Calls the Gemini generateContent REST API."""

    BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "gemini-2.0-flash",
        timeout: float = 45.0,
    ) -> None:
        self.api_key = api_key or settings.gemini_api_key
        self.model = model
        self.timeout = timeout

    def generate_schedule(
        self, context: SchedulingContext, prompt: str
    ) -> ProviderResult:
        if not self.api_key:
            raise ProviderError("Gemini API key is not configured")

        try:
            response = httpx.post(
                f"{self.BASE_URL}/models/{self.model}:generateContent",
                params={"key": self.api_key},
                json={
                    "contents": [
                        {"role": "user", "parts": [{"text": prompt}]}
                    ],
                    "generationConfig": {
                        "responseMimeType": "application/json",
                        "temperature": 0.2,
                    },
                },
                timeout=self.timeout,
            )
            response.raise_for_status()
            payload = response.json()
            text = (
                payload.get("candidates", [{}])[0]
                .get("content", {})
                .get("parts", [{}])[0]
                .get("text", "")
            )
            if not text:
                raise ProviderError("Gemini returned an empty response")
            return self._parse_output(text)
        except httpx.HTTPError as exc:
            raise ProviderError(f"Gemini request failed: {exc}") from exc
        except (KeyError, IndexError, json.JSONDecodeError) as exc:
            raise ProviderError(f"Could not parse Gemini response: {exc}") from exc

    def _parse_output(self, text: str) -> ProviderResult:
        data = json.loads(text)
        items = []
        for entry in data.get("items", []):
            task_id = entry.get("task_id")
            if not task_id:
                raise ProviderError("Gemini output item missing task_id")
            items.append(
                ProposedBlock(
                    task_id=UUID(task_id),
                    task_title=entry.get("task_title", ""),
                    start=_parse_datetime(entry["start"]),
                    end=_parse_datetime(entry["end"]),
                    reason=entry.get("reason", ""),
                )
            )
        return ProviderResult(
            items=items,
            reasoning=data.get("reasoning", ""),
        )


class HeuristicProvider:
    """Deterministic fallback scheduler: first-fit by priority and deadline.

    This keeps the product working when no Gemini key is configured or when
    the model is unavailable, and doubles as a deterministic test double.
    """

    def generate_schedule(
        self, context: SchedulingContext, prompt: str
    ) -> ProviderResult:
        fixed_tasks = [task for task in context.tasks if task.is_fixed]
        flexible = sorted(
            (task for task in context.tasks if not task.is_fixed),
            key=lambda task: (
                -PRIORITY_RANK.get(task.priority, 1),
                task.deadline is None,
                task.deadline or datetime.max.replace(tzinfo=ZoneInfo("UTC")),
            ),
        )

        available = list(context.free_slots)
        blocks: list[ProposedBlock] = []
        deferred: list[str] = []
        self._buffer = context.buffer_minutes
        self._max_chunk = context.max_chunk_minutes

        for task in fixed_tasks:
            placement = self._place_fixed_task(task, available)
            if placement is None:
                deferred.append(task.title)
                continue
            placed, remaining = placement
            blocks.extend(placed)
            available = remaining

        for task in flexible:
            placement = self._place_task(task, available)
            if placement is None:
                deferred.append(task.title)
                continue
            placed, remaining = placement
            blocks.extend(placed)
            available = remaining

        scheduled_ids = {block.task_id for block in blocks}
        total_count = len(context.tasks)
        scheduled_count = len(scheduled_ids)
        if scheduled_count == total_count:
            summary = (
                f"Scheduled all {total_count} task(s) into the available time, "
                f"keeping a {context.buffer_minutes} minute buffer between blocks."
            )
        else:
            summary = (
                f"Scheduled {scheduled_count} of {total_count} task(s). "
                f"{len(deferred)} task(s) could not fit and were deferred: "
                f"{', '.join(deferred)}."
            )
        return ProviderResult(items=blocks, reasoning=summary)

    def _place_fixed_task(
        self,
        task,
        available: list[TimeSlot],
    ) -> tuple[list[ProposedBlock], list[TimeSlot]] | None:
        window = TimeSlot(task.start_at, task.end_at)
        if window.end <= window.start:
            return None
        if task.deadline is not None and window.end > task.deadline:
            return None
        for index, slot in enumerate(available):
            if slot.start <= window.start and window.end <= slot.end:
                blocks = [
                    ProposedBlock(
                        task_id=task.id,
                        task_title=task.title,
                        start=window.start,
                        end=window.end,
                        reason="fixed event, scheduled at its exact window",
                    )
                ]
                remaining = list(available)
                carved: list[TimeSlot] = []
                if slot.start < window.start:
                    carved.append(TimeSlot(slot.start, window.start))
                if window.end < slot.end:
                    carved.append(TimeSlot(window.end, slot.end))
                remaining[index:index + 1] = carved
                remaining.sort(key=lambda slot: (slot.start, slot.end))
                return blocks, remaining
        return None

    def _place_task(
        self,
        task,
        available: list[TimeSlot],
    ) -> tuple[list[ProposedBlock], list[TimeSlot]] | None:
        duration = task.duration_minutes
        deadline = task.deadline
        max_chunk = self._max_chunk_minutes()
        remaining_slots = list(available)
        blocks: list[ProposedBlock] = []
        remaining_duration = duration
        total_parts = max(1, math.ceil(duration / max_chunk))

        while remaining_duration > 0:
            placed_in_this_pass = False
            for index, slot in enumerate(remaining_slots):
                if deadline is not None and slot.start > deadline:
                    continue
                chunk = min(remaining_duration, max_chunk)
                if slot.duration_minutes < chunk:
                    continue
                part = len(blocks) + 1
                blocks.append(
                    ProposedBlock(
                        task_id=task.id,
                        task_title=task.title,
                        start=slot.start,
                        end=slot.start + timedelta(minutes=chunk),
                        reason=self._reason_for(task, slot.start, part, total_parts),
                    )
                )
                remaining_duration -= chunk
                after = slot.start + timedelta(
                    minutes=chunk + self._buffer_minutes()
                )
                if after < slot.end:
                    remaining_slots[index] = TimeSlot(after, slot.end)
                else:
                    del remaining_slots[index]
                remaining_slots.sort(key=lambda slot: (slot.start, slot.end))
                placed_in_this_pass = True
                break
            if not placed_in_this_pass:
                break

        if remaining_duration > 0:
            return None
        return blocks, remaining_slots

    def _buffer_minutes(self) -> int:
        return getattr(self, "_buffer", 0)

    def _max_chunk_minutes(self) -> int:
        return getattr(self, "_max_chunk", 90)

    def _reason_for(
        self, task, start: datetime, part: int = 1, total_parts: int = 1
    ) -> str:
        reasons = []
        if task.priority == TaskPriority.high:
            reasons.append("high priority")
        if task.deadline is not None:
            reasons.append(
                f"deadline {task.deadline.date().isoformat()}, scheduled before it"
            )
        if not reasons:
            reasons.append("first available slot")
        reason = (
            f"Scheduled at {start.strftime('%a %H:%M')} due to "
            f"{' and '.join(reasons)}"
        )
        if total_parts > 1:
            reason = f"{reason} (part {part} of {total_parts})"
        return reason
