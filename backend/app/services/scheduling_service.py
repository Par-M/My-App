import copy
import uuid
from datetime import date
from datetime import datetime
from datetime import timedelta
from datetime import timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.ai_recommendation import AIRecommendation
from app.models.ai_recommendation import RecommendationStatus
from app.models.calendar_block import CalendarBlock
from app.models.task import Task
from app.models.task import TaskProductivity
from app.models.task import TaskStatus
from app.models.user_preference import UserPreference
from app.schemas.calendar import BusyTime
from app.schemas.schedule import ScheduleGenerateRequest
from app.services.scheduling.context import ProposedBlock
from app.services.scheduling.context import ProviderResult
from app.services.scheduling.context import SchedulingContext
from app.services.scheduling.context import TaskContext
from app.services.scheduling.context import TimeSlot
from app.services.scheduling.free_slots import find_free_slots
from app.services.scheduling.providers import AIProvider
from app.services.scheduling.providers import HeuristicProvider
from app.services.scheduling.providers import ProviderError
from app.services.scheduling.providers import default_provider
from app.services.scheduling.prompt_builder import build_prompt
from app.services.scheduling.validator import validate_schedule


class RecommendationNotFoundError(Exception):
    pass


class RecommendationNotAcceptableError(Exception):
    pass


class NoTasksToScheduleError(Exception):
    pass


def _parse(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=_utc())
    return parsed


def _utc():
    from zoneinfo import ZoneInfo

    return ZoneInfo("UTC")


DEFAULT_SCHEDULE_HORIZON_DAYS = 7


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _item_to_dict(block: ProposedBlock) -> dict:
    return {
        "task_id": str(block.task_id),
        "task_title": block.task_title,
        "start": block.start.isoformat(),
        "end": block.end.isoformat(),
        "reason": block.reason,
        "accepted": False,
    }


class SchedulingService:
    def __init__(
        self,
        db: Session,
        user_id: uuid.UUID,
        provider: AIProvider | None = None,
    ) -> None:
        self.db = db
        self.user_id = user_id
        self.provider = provider or default_provider()
        self.heuristic = HeuristicProvider()

    # ------------------------------------------------------------------
    # Input gathering
    # ------------------------------------------------------------------
    def _active_tasks(self, task_ids: list[uuid.UUID] | None) -> list[Task]:
        statement = select(Task).where(
            Task.user_id == self.user_id,
            Task.is_archived.is_(False),
            Task.status != TaskStatus.completed,
        )
        if task_ids:
            statement = statement.where(Task.id.in_(task_ids))
        tasks = list(self.db.scalars(statement).all())

        if tasks:
            scheduled_ids = set(
                self.db.scalars(
                    select(CalendarBlock.task_id).where(
                        CalendarBlock.user_id == self.user_id,
                    )
                ).all()
            )
            tasks = [t for t in tasks if t.id not in scheduled_ids]

        return tasks

    def _preferences(self) -> UserPreference:
        preference = self.db.scalar(
            select(UserPreference).where(UserPreference.user_id == self.user_id)
        )
        if preference is None:
            preference = UserPreference(user_id=self.user_id)
            self.db.add(preference)
            self.db.flush()
        return preference

    PRODUCTIVITY_FACTORS = {
        TaskProductivity.fast: 0.8,
        TaskProductivity.moderate: 1.0,
        TaskProductivity.slow: 1.35,
    }

    def _productivity_factors(self, tasks: list[Task]) -> dict[uuid.UUID, float]:
        """Duration multipliers derived from the user's productivity history.

        A rated task uses its own rating; unrated tasks inherit the user's
        average pace so the schedule gives more (or less) time accordingly.
        """
        rated = list(
            self.db.scalars(
                select(Task).where(
                    Task.user_id == self.user_id,
                    Task.status == TaskStatus.completed,
                    Task.productivity.isnot(None),
                )
            ).all()
        )
        if rated:
            aggregate = sum(
                self.PRODUCTIVITY_FACTORS.get(task.productivity, 1.0)
                for task in rated
            ) / len(rated)
        else:
            aggregate = 1.0
        return {
            task.id: self.PRODUCTIVITY_FACTORS.get(task.productivity, aggregate)
            for task in tasks
        }

    def _build_context(
        self,
        tasks: list[Task],
        preference: UserPreference,
        request: ScheduleGenerateRequest,
    ) -> SchedulingContext:
        tz = ZoneInfo(request.timezone)
        today = _utc_now().astimezone(tz).date()
        effective_end = today + timedelta(days=DEFAULT_SCHEDULE_HORIZON_DAYS)
        for task in tasks:
            for when in (task.deadline, task.end_at):
                if when is not None:
                    day = when.astimezone(tz).date()
                    if day > effective_end:
                        effective_end = day
        dates = [
            today + timedelta(days=offset)
            for offset in range((effective_end - today).days + 1)
        ]
        factors = self._productivity_factors(tasks)
        by_id = {task.id: task for task in tasks}
        now = _utc_now()
        context = SchedulingContext(
            tasks=[
                TaskContext(
                    id=task.id,
                    title=task.title,
                    deadline=task.deadline,
                    duration_minutes=max(
                        5,
                        round((task.estimated_duration or 30) * factors.get(task.id, 1.0)),
                    ),
                    priority=task.priority,
                    energy_level=preference.energy_level,
                    start_at=task.start_at,
                    end_at=task.end_at,
                    before_task_titles=tuple(
                        by_id[t].title
                        for t in (task.before_task_ids or [])
                        if t in by_id
                    ),
                    after_task_titles=tuple(
                        by_id[t].title
                        for t in (task.after_task_ids or [])
                        if t in by_id
                    ),
                    is_overdue=(
                        task.deadline is not None and task.deadline < now
                    ),
                )
                for task in tasks
            ],
            dates=dates,
            timezone=request.timezone,
            busy_times=request.busy_times,
            work_start_hour=preference.work_hours_start,
            work_end_hour=preference.work_hours_end,
            buffer_minutes=preference.buffer_minutes,
            energy_level=preference.energy_level,
            max_daily_hours=preference.max_daily_hours,
        )
        context.free_slots = find_free_slots(
            dates=dates,
            busy=[
                *context.busy_times,
                TimeSlot(
                    start=_utc_now(),
                    end=_utc_now() + timedelta(minutes=5),
                ),
            ],
            start_hour=context.work_start_hour,
            end_hour=context.work_end_hour,
            timezone=context.timezone,
        )
        return context

    # ------------------------------------------------------------------
    # Schedule generation
    # ------------------------------------------------------------------
    def generate(self, request: ScheduleGenerateRequest) -> AIRecommendation:
        tasks = self._active_tasks(request.task_ids)
        preference = self._preferences()
        context = self._build_context(tasks, preference, request)

        if not tasks:
            return self._store_pending(
                context,
                reasoning="No active tasks to schedule.",
                items=[],
                meta={
                    "overcommitted": False,
                    "risk": None,
                    "deferred_tasks": [],
                    "free_slots": self._serialize_free_slots(context),
                    "scheduleable_hours": round(context.scheduleable_minutes / 60, 1),
                    "required_hours": 0.0,
                    "provider": "none",
                    "warnings": [],
                },
                request=request,
            )

        prompt = build_prompt(context)
        result = None
        validation = None
        failure: str | None = None
        provider_used = "gemini"

        if settings.gemini_api_key:
            try:
                result = self.provider.generate_schedule(context, prompt)
                validation = validate_schedule(result.items, context)
                if not validation.is_valid:
                    result = self.provider.generate_schedule(context, prompt)
                    validation = validate_schedule(result.items, context)
            except ProviderError as exc:
                failure = str(exc)

        if result is None or (validation is not None and not validation.is_valid):
            provider_used = "heuristic_fallback"
            try:
                result = self.heuristic.generate_schedule(context, prompt)
                validation = validate_schedule(result.items, context)
            except Exception as exc:  # pragma: no cover - defensive
                failure = str(exc)

        if result is None:
            return self._store_failed(context, failure, request=request)

        meta = self._build_meta(context, result, validation, provider_used)
        return self._store_pending(
            context,
            reasoning=result.reasoning,
            items=result.items,
            meta=meta,
            request=request,
        )

    def _build_meta(self, context, result, validation, provider_used: str) -> dict:
        scheduled_ids = {block.task_id for block in result.items}
        deferred = [
            task.title for task in context.tasks if task.id not in scheduled_ids
        ]
        overcommitted = bool(deferred) or (
            context.required_minutes > context.scheduleable_minutes
        )
        risk = None
        if context.required_minutes > context.scheduleable_minutes:
            risk = (
                "No feasible schedule for all tasks: more work is required "
                "than free time available. Tasks marked as deferred may need "
                "to be pushed out or completed first."
            )
        elif deferred:
            risk = "Some tasks could not be scheduled in this window and were deferred."
        warnings = list(validation.warnings) if validation else []
        return {
            "overcommitted": overcommitted,
            "risk": risk,
            "deferred_tasks": deferred,
            "free_slots": self._serialize_free_slots(context),
            "scheduleable_hours": round(context.scheduleable_minutes / 60, 1),
            "required_hours": round(context.required_minutes / 60, 1),
            "provider": provider_used,
            "warnings": warnings,
        }

    def _serialize_free_slots(self, context) -> list[dict]:
        return [
            {"start": slot.start.isoformat(), "end": slot.end.isoformat()}
            for slot in context.free_slots
        ]

    def _store_pending(
        self,
        context,
        *,
        reasoning,
        items,
        meta,
        request: ScheduleGenerateRequest,
    ) -> AIRecommendation:
        recommendation = AIRecommendation(
            user_id=self.user_id,
            status=RecommendationStatus.pending,
            accepted=False,
            reasoning=reasoning,
            recommendation={
                "items": [_item_to_dict(block) for block in items],
                "meta": meta,
                "request": request.model_dump(mode="json"),
            },
        )
        self.db.add(recommendation)
        self.db.commit()
        self.db.refresh(recommendation)
        return recommendation

    def _store_failed(
        self,
        context,
        failure: str | None,
        *,
        request: ScheduleGenerateRequest,
    ) -> AIRecommendation:
        recommendation = AIRecommendation(
            user_id=self.user_id,
            status=RecommendationStatus.pending,
            accepted=False,
            reasoning="Schedule generation failed. The current schedule was "
            "preserved and will be retried automatically.",
            failure_reason=failure or "Unknown scheduling error",
            retry_at=datetime.now(_utc()) + timedelta(minutes=5),
            recommendation={
                "items": [],
                "meta": {
                    "overcommitted": False,
                    "risk": None,
                    "deferred_tasks": [],
                    "free_slots": self._serialize_free_slots(context),
                    "scheduleable_hours": round(
                        context.scheduleable_minutes / 60, 1
                    ),
                    "required_hours": round(context.required_minutes / 60, 1),
                    "provider": "failed",
                    "warnings": [],
                },
                "request": request.model_dump(mode="json"),
            },
        )
        self.db.add(recommendation)
        self.db.commit()
        self.db.refresh(recommendation)
        return recommendation

    def _restore_request(self, stored: dict) -> ScheduleGenerateRequest:
        raw = stored.get("request")
        if not raw:
            raise RecommendationNotAcceptableError(
                "This proposal has no stored request data, so a single "
                "item cannot be regenerated. Generate a fresh proposal instead."
            )
        return ScheduleGenerateRequest(
            start_date=date.fromisoformat(raw["start_date"]),
            end_date=date.fromisoformat(raw["end_date"]),
            timezone=raw["timezone"],
            busy_times=[
                BusyTime(start=_parse(entry["start"]), end=_parse(entry["end"]))
                for entry in raw.get("busy_times", [])
            ],
            task_ids=(
                [uuid.UUID(value) for value in raw["task_ids"]]
                if raw.get("task_ids")
                else None
            ),
        )

    # ------------------------------------------------------------------
    # Recommendations lifecycle
    # ------------------------------------------------------------------
    def get_recommendation(self, recommendation_id: uuid.UUID) -> AIRecommendation:
        recommendation = self.db.scalar(
            select(AIRecommendation).where(
                AIRecommendation.id == recommendation_id,
                AIRecommendation.user_id == self.user_id,
            )
        )
        if recommendation is None:
            raise RecommendationNotFoundError("Recommendation not found")
        return recommendation

    def list_recommendations(
        self, status: RecommendationStatus | None = None, limit: int = 50
    ) -> list[AIRecommendation]:
        statement = select(AIRecommendation).where(
            AIRecommendation.user_id == self.user_id
        )
        if status is not None:
            statement = statement.where(AIRecommendation.status == status)
        statement = statement.order_by(
            AIRecommendation.created_at.desc()
        ).limit(limit)
        return list(self.db.scalars(statement).all())

    def accept(
        self, recommendation_id: uuid.UUID
    ) -> tuple[AIRecommendation, list[CalendarBlock]]:
        recommendation = self.get_recommendation(recommendation_id)
        if recommendation.status != RecommendationStatus.pending:
            raise RecommendationNotAcceptableError(
                "Only pending recommendations can be accepted"
            )
        items = copy.deepcopy((recommendation.recommendation or {}).get("items", []))
        if not items:
            raise RecommendationNotAcceptableError(
                "Recommendation has no schedule items to accept"
            )

        blocks: list[CalendarBlock] = []
        for item in items:
            if item.get("accepted"):
                continue
            block = CalendarBlock(
                user_id=self.user_id,
                task_id=uuid.UUID(item["task_id"]),
                title=item["task_title"],
                start_at=_parse(item["start"]),
                end_at=_parse(item["end"]),
            )
            self.db.add(block)
            blocks.append(block)
            item["accepted"] = True

        stored = copy.deepcopy(recommendation.recommendation or {})
        stored["items"] = items
        recommendation.recommendation = stored
        recommendation.status = RecommendationStatus.accepted
        recommendation.accepted = True
        self.db.flush()
        self.db.commit()
        for block in blocks:
            self.db.refresh(block)
        self.db.refresh(recommendation)
        return recommendation, blocks

    def reject(self, recommendation_id: uuid.UUID) -> AIRecommendation:
        recommendation = self.get_recommendation(recommendation_id)
        if recommendation.status != RecommendationStatus.pending:
            raise RecommendationNotAcceptableError(
                "Only pending recommendations can be rejected"
            )
        recommendation.status = RecommendationStatus.rejected
        recommendation.accepted = False
        self.db.commit()
        self.db.refresh(recommendation)
        return recommendation

    def accept_item(
        self, recommendation_id: uuid.UUID, item_index: int
    ) -> tuple[AIRecommendation, list[CalendarBlock]]:
        recommendation = self.get_recommendation(recommendation_id)
        if recommendation.status != RecommendationStatus.pending:
            raise RecommendationNotAcceptableError(
                "Only pending recommendations can be approved"
            )
        items = copy.deepcopy((recommendation.recommendation or {}).get("items", []))
        if not 0 <= item_index < len(items):
            raise RecommendationNotAcceptableError(
                "Proposed item not found"
            )
        item = items[item_index]
        if item.get("accepted"):
            raise RecommendationNotAcceptableError(
                "This item has already been approved"
            )

        block = CalendarBlock(
            user_id=self.user_id,
            task_id=uuid.UUID(item["task_id"]),
            title=item["task_title"],
            start_at=_parse(item["start"]),
            end_at=_parse(item["end"]),
        )
        self.db.add(block)
        item["accepted"] = True
        stored = copy.deepcopy(recommendation.recommendation or {})
        stored["items"] = items
        recommendation.recommendation = stored
        if all(entry.get("accepted") for entry in items):
            recommendation.status = RecommendationStatus.accepted
            recommendation.accepted = True
        self.db.flush()
        self.db.commit()
        self.db.refresh(block)
        self.db.refresh(recommendation)
        return recommendation, [block]

    def redo_item(
        self, recommendation_id: uuid.UUID, item_index: int
    ) -> AIRecommendation:
        recommendation = self.get_recommendation(recommendation_id)
        if recommendation.status != RecommendationStatus.pending:
            raise RecommendationNotAcceptableError(
                "Only pending recommendations can be regenerated"
            )
        stored = recommendation.recommendation or {}
        items = stored.get("items", [])
        if not 0 <= item_index < len(items):
            raise RecommendationNotAcceptableError("Proposed item not found")

        target_id = uuid.UUID(items[item_index]["task_id"])
        if any(
            entry.get("accepted")
            for entry in items
            if entry["task_id"] == str(target_id)
        ):
            raise RecommendationNotAcceptableError(
                "Approved items cannot be regenerated. Redo a proposal item "
                "before approving it."
            )
        request = self._restore_request(stored)
        task = self.db.scalar(
            select(Task).where(
                Task.id == target_id,
                Task.user_id == self.user_id,
            )
        )
        if task is None:
            raise RecommendationNotFoundError("Task not found")
        preference = self._preferences()

        redo_request = ScheduleGenerateRequest(
            start_date=request.start_date,
            end_date=request.end_date,
            timezone=request.timezone,
            busy_times=[
                *request.busy_times,
                *[
                    BusyTime(start=_parse(entry["start"]), end=_parse(entry["end"]))
                    for entry in items
                    if entry["task_id"] != str(target_id)
                ],
            ],
            task_ids=[target_id],
        )
        redo_context = self._build_context([task], preference, redo_request)

        result = None
        provider_used = "gemini"
        if settings.gemini_api_key:
            try:
                result = self.provider.generate_schedule(
                    redo_context, build_prompt(redo_context)
                )
            except ProviderError:
                result = None
        if result is None:
            provider_used = "heuristic_fallback"
            try:
                result = self.heuristic.generate_schedule(
                    redo_context, build_prompt(redo_context)
                )
            except Exception as exc:  # pragma: no cover - defensive
                result = None

        new_blocks = (
            [block for block in result.items if block.task_id == target_id]
            if result is not None
            else []
        )
        if not new_blocks:
            note = (
                "Could not find a better slot for this task; the original "
                "proposal was kept."
            )
            recommendation.reasoning = "\n".join(
                part for part in [recommendation.reasoning, note] if part
            )
            self.db.commit()
            self.db.refresh(recommendation)
            return recommendation

        replaced = [
            entry for entry in items if entry["task_id"] != str(target_id)
        ]
        first_index = next(
            (
                index
                for index, entry in enumerate(items)
                if entry["task_id"] == str(target_id)
            ),
            0,
        )
        fresh_items = [_item_to_dict(block) for block in new_blocks]
        replaced[first_index:first_index] = fresh_items

        full_context = self._build_context(
            self._active_tasks(request.task_ids), preference, request
        )
        full_result = ProviderResult(
            items=[
                ProposedBlock(
                    task_id=uuid.UUID(entry["task_id"]),
                    task_title=entry["task_title"],
                    start=_parse(entry["start"]),
                    end=_parse(entry["end"]),
                    reason=entry.get("reason", ""),
                )
                for entry in replaced
            ],
            reasoning=result.reasoning,
        )
        validation = validate_schedule(full_result.items, full_context)
        meta = self._build_meta(full_context, full_result, validation, provider_used)

        stored["items"] = replaced
        stored["meta"] = meta
        recommendation.reasoning = result.reasoning or recommendation.reasoning
        self.db.commit()
        self.db.refresh(recommendation)
        return recommendation
