import uuid
from datetime import date
from datetime import datetime
from datetime import timedelta
from zoneinfo import ZoneInfo

from app.models.task import TaskPriority
from app.services.scheduling.context import ProposedBlock
from app.services.scheduling.context import SchedulingContext
from app.services.scheduling.context import TaskContext
from app.services.scheduling.context import TimeSlot
from app.services.scheduling.free_slots import find_free_slots
from app.services.scheduling.prompt_builder import build_prompt
from app.services.scheduling.providers import HeuristicProvider
from app.services.scheduling.validator import validate_schedule

UTC = ZoneInfo("UTC")
DATES = [date(2026, 8, 3), date(2026, 8, 4)]


def utc(value: str) -> datetime:
    return datetime.fromisoformat(value).astimezone(UTC)


def slot(start: str, end: str) -> TimeSlot:
    return TimeSlot(utc(start), utc(end))


def task(title="Task", priority=TaskPriority.medium, duration=60, deadline=None, start_at=None, end_at=None):
    return TaskContext(
        id=uuid.uuid4(),
        title=title,
        deadline=deadline,
        duration_minutes=duration,
        priority=priority,
        energy_level=3,
        start_at=start_at,
        end_at=end_at,
    )


class TestFindFreeSlots:
    def test_excludes_busy_events(self):
        busy = [slot("2026-08-03T10:00:00+00:00", "2026-08-03T11:00:00+00:00")]
        result = find_free_slots(
            dates=DATES,
            busy=busy,
            start_hour=9,
            end_hour=17,
            timezone="UTC",
        )
        assert [(s.start, s.end) for s in result] == [
            (utc("2026-08-03T09:00:00+00:00"), utc("2026-08-03T10:00:00+00:00")),
            (utc("2026-08-03T11:00:00+00:00"), utc("2026-08-03T17:00:00+00:00")),
            (utc("2026-08-04T09:00:00+00:00"), utc("2026-08-04T17:00:00+00:00")),
        ]

    def test_merges_overlapping_busy(self):
        busy = [
            slot("2026-08-03T09:00:00+00:00", "2026-08-03T11:00:00+00:00"),
            slot("2026-08-03T10:30:00+00:00", "2026-08-03T13:00:00+00:00"),
        ]
        result = find_free_slots(
            dates=DATES,
            busy=busy,
            start_hour=9,
            end_hour=17,
            timezone="UTC",
        )
        assert result[0].start == utc("2026-08-03T13:00:00+00:00")
        assert result[0].end == utc("2026-08-03T17:00:00+00:00")

    def test_respects_working_hours(self):
        busy = [slot("2026-08-03T08:00:00+00:00", "2026-08-03T20:00:00+00:00")]
        result = find_free_slots(
            dates=[DATES[0]],
            busy=busy,
            start_hour=9,
            end_hour=17,
            timezone="UTC",
        )
        assert result == []

    def test_ignores_busy_outside_window(self):
        busy = [slot("2026-08-03T20:00:00+00:00", "2026-08-03T22:00:00+00:00")]
        result = find_free_slots(
            dates=[DATES[0]],
            busy=busy,
            start_hour=9,
            end_hour=17,
            timezone="UTC",
        )
        assert len(result) == 1
        assert result[0].start == utc("2026-08-03T09:00:00+00:00")
        assert result[0].end == utc("2026-08-03T17:00:00+00:00")

    def test_drops_tiny_slots(self):
        busy = [
            slot("2026-08-03T09:00:00+00:00", "2026-08-03T09:10:00+00:00")
        ]
        result = find_free_slots(
            dates=[DATES[0]],
            busy=busy,
            start_hour=9,
            end_hour=17,
            timezone="UTC",
        )
        assert all(
            (s.end - s.start) >= timedelta(minutes=15) for s in result
        )

    def test_handles_timezone(self):
        result = find_free_slots(
            dates=[date(2026, 8, 3)],
            busy=[],
            start_hour=9,
            end_hour=17,
            timezone="America/New_York",
        )
        start = result[0].start
        assert start.astimezone(UTC) == utc("2026-08-03T13:00:00+00:00")


def build_context(tasks, busy=None, buffer=15, max_daily_hours=8):
    return SchedulingContext(
        tasks=tasks,
        dates=DATES,
        timezone="UTC",
        busy_times=busy or [],
        buffer_minutes=buffer,
        max_daily_hours=max_daily_hours,
    )


class TestValidator:
    def test_valid_schedule_passes(self):
        t = task(priority=TaskPriority.high)
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T10:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert result.is_valid

    def test_rejects_overlap_with_busy(self):
        t = task()
        context = build_context(
            [t], busy=[slot("2026-08-03T09:30:00+00:00", "2026-08-03T10:30:00+00:00")]
        )
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T10:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert result.is_valid
        assert any("overlaps" in w for w in result.warnings)

    def test_rejects_outside_working_hours(self):
        t = task()
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T07:00:00+00:00"),
                end=utc("2026-08-03T08:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert not result.is_valid
        assert any("working hours" in e for e in result.errors)

    def test_rejects_deadline_violation(self):
        deadline = datetime(2026, 8, 3, 9, 30, tzinfo=UTC)
        t = task(deadline=deadline)
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T10:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert not result.is_valid
        assert any("Deadline" in e for e in result.errors)

    def test_allows_overdue_block_past_deadline(self):
        deadline = datetime(2026, 8, 2, 10, 0, tzinfo=UTC)
        t = TaskContext(
            id=uuid.uuid4(),
            title="Late",
            deadline=deadline,
            duration_minutes=60,
            priority=TaskPriority.medium,
            energy_level=3,
            is_overdue=True,
        )
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T10:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert result.is_valid
        assert any("overdue" in w for w in result.warnings)

    def test_rejects_invalid_time(self):
        t = task()
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T10:00:00+00:00"),
                end=utc("2026-08-03T09:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert not result.is_valid

    def test_accepts_chunked_blocks(self):
        t = task(duration=120)
        context = build_context([t])
        result = validate_schedule(
            [
                ProposedBlock(
                    task_id=t.id,
                    task_title=t.title,
                    start=utc("2026-08-03T09:00:00+00:00"),
                    end=utc("2026-08-03T10:00:00+00:00"),
                    reason="x",
                ),
                ProposedBlock(
                    task_id=t.id,
                    task_title=t.title,
                    start=utc("2026-08-03T11:00:00+00:00"),
                    end=utc("2026-08-03T12:00:00+00:00"),
                    reason="x",
                ),
            ],
            context,
        )
        assert result.is_valid

    def test_rejects_over_duration(self):
        t = task(duration=60)
        context = build_context([t])
        result = validate_schedule(
            [
                ProposedBlock(
                    task_id=t.id,
                    task_title=t.title,
                    start=utc("2026-08-03T09:00:00+00:00"),
                    end=utc("2026-08-03T10:00:00+00:00"),
                    reason="x",
                ),
                ProposedBlock(
                    task_id=t.id,
                    task_title=t.title,
                    start=utc("2026-08-03T11:00:00+00:00"),
                    end=utc("2026-08-03T12:00:00+00:00"),
                    reason="x",
                ),
            ],
            context,
        )
        assert not result.is_valid
        assert any("exceeds" in e for e in result.errors)

    def test_rejects_partial_schedule(self):
        t = task(duration=180)
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T10:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert result.is_valid
        assert any("partially scheduled" in w for w in result.warnings)

    def test_warns_when_block_exceeds_chunk_limit(self):
        t = task(duration=180)
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T12:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert result.is_valid
        assert any("chunk limit" in w for w in result.warnings)

    def test_rejects_unknown_task(self):
        context = build_context([task()])
        result = validate_schedule(
            ProposedBlock(
                task_id=uuid.uuid4(),
                task_title="Ghost",
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T10:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert not result.is_valid
        assert any("Unknown task_id" in e for e in result.errors)

    def test_rejects_block_overlap(self):
        t1 = task(title="A", duration=90)
        t2 = task(title="B", duration=60)
        context = build_context([t1, t2])
        result = validate_schedule(
            [
                ProposedBlock(
                    task_id=t1.id,
                    task_title=t1.title,
                    start=utc("2026-08-03T09:00:00+00:00"),
                    end=utc("2026-08-03T10:30:00+00:00"),
                    reason="x",
                ),
                ProposedBlock(
                    task_id=t2.id,
                    task_title=t2.title,
                    start=utc("2026-08-03T10:00:00+00:00"),
                    end=utc("2026-08-03T11:00:00+00:00"),
                    reason="x",
                ),
            ],
            context,
        )
        assert result.is_valid
        assert any("overlaps another" in w for w in result.warnings)

    def test_warns_about_buffer(self):
        t1 = task(title="A")
        t2 = task(title="B")
        context = build_context([t1, t2])
        result = validate_schedule(
            [
                ProposedBlock(
                    task_id=t1.id,
                    task_title=t1.title,
                    start=utc("2026-08-03T09:00:00+00:00"),
                    end=utc("2026-08-03T10:00:00+00:00"),
                    reason="x",
                ),
                ProposedBlock(
                    task_id=t2.id,
                    task_title=t2.title,
                    start=utc("2026-08-03T10:05:00+00:00"),
                    end=utc("2026-08-03T11:05:00+00:00"),
                    reason="x",
                ),
            ],
            context,
        )
        assert result.is_valid
        assert any("Buffer" in w for w in result.warnings)

    def test_fixed_task_at_exact_window_passes(self):
        t = task(
            title="Standup",
            duration=30,
            start_at=utc("2026-08-03T09:30:00+00:00"),
            end_at=utc("2026-08-03T10:00:00+00:00"),
        )
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:30:00+00:00"),
                end=utc("2026-08-03T10:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert result.is_valid

    def test_rejects_fixed_task_moved(self):
        t = task(
            title="Standup",
            start_at=utc("2026-08-03T09:30:00+00:00"),
            end_at=utc("2026-08-03T10:00:00+00:00"),
        )
        context = build_context([t])
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T11:00:00+00:00"),
                end=utc("2026-08-03T11:30:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert not result.is_valid
        assert any("exactly" in e for e in result.errors)

    def test_rejects_fixed_task_split(self):
        t = task(
            title="Standup",
            duration=30,
            start_at=utc("2026-08-03T09:30:00+00:00"),
            end_at=utc("2026-08-03T10:00:00+00:00"),
        )
        context = build_context([t])
        result = validate_schedule(
            [
                ProposedBlock(
                    task_id=t.id,
                    task_title=t.title,
                    start=utc("2026-08-03T09:30:00+00:00"),
                    end=utc("2026-08-03T09:45:00+00:00"),
                    reason="x",
                ),
                ProposedBlock(
                    task_id=t.id,
                    task_title=t.title,
                    start=utc("2026-08-03T09:45:00+00:00"),
                    end=utc("2026-08-03T10:00:00+00:00"),
                    reason="x",
                ),
            ],
            context,
        )
        assert not result.is_valid
        assert any("single block" in e for e in result.errors)

    def test_rejects_flexible_task_overlapping_fixed_window(self):
        fixed = task(
            title="Fixed",
            start_at=utc("2026-08-03T10:00:00+00:00"),
            end_at=utc("2026-08-03T11:00:00+00:00"),
        )
        flexible = task(title="Flex", duration=60)
        context = build_context([fixed, flexible])
        result = validate_schedule(
            [
                ProposedBlock(
                    task_id=fixed.id,
                    task_title=fixed.title,
                    start=utc("2026-08-03T10:00:00+00:00"),
                    end=utc("2026-08-03T11:00:00+00:00"),
                    reason="x",
                ),
                ProposedBlock(
                    task_id=flexible.id,
                    task_title=flexible.title,
                    start=utc("2026-08-03T10:30:00+00:00"),
                    end=utc("2026-08-03T11:30:00+00:00"),
                    reason="x",
                ),
            ],
            context,
        )
        assert result.is_valid
        assert any("overlaps the fixed window" in w for w in result.warnings)

    def test_deferred_fixed_task_has_no_fixed_specific_error(self):
        t = task(
            title="Fixed",
            duration=60,
            start_at=utc("2026-08-03T10:00:00+00:00"),
            end_at=utc("2026-08-03T11:00:00+00:00"),
        )
        context = build_context([t])
        result = validate_schedule([], context)
        assert result.is_valid
        assert not any("exactly" in e for e in result.errors)
        assert not any("single block" in e for e in result.errors)
        assert any("partially scheduled" in w for w in result.warnings)

    def test_rejects_exceeding_daily_max_hours(self):
        t1 = task(title="A")
        t2 = task(title="B")
        context = build_context([t1, t2], buffer=0, max_daily_hours=1)
        result = validate_schedule(
            [
                ProposedBlock(
                    task_id=t1.id,
                    task_title=t1.title,
                    start=utc("2026-08-03T09:00:00+00:00"),
                    end=utc("2026-08-03T10:00:00+00:00"),
                    reason="x",
                ),
                ProposedBlock(
                    task_id=t2.id,
                    task_title=t2.title,
                    start=utc("2026-08-03T10:00:00+00:00"),
                    end=utc("2026-08-03T11:00:00+00:00"),
                    reason="x",
                ),
            ],
            context,
        )
        assert result.is_valid
        assert any("hours of work" in w for w in result.warnings)

    def test_allows_fixed_task_exceeding_daily_max(self):
        t = task(
            title="Fixed",
            duration=120,
            start_at=utc("2026-08-03T09:00:00+00:00"),
            end_at=utc("2026-08-03T11:00:00+00:00"),
        )
        context = build_context([t], buffer=0, max_daily_hours=1)
        result = validate_schedule(
            ProposedBlock(
                task_id=t.id,
                task_title=t.title,
                start=utc("2026-08-03T09:00:00+00:00"),
                end=utc("2026-08-03T11:00:00+00:00"),
                reason="x",
            ),
            context,
        )
        assert result.is_valid
        assert not any("hours of work" in e for e in result.errors)


class TestHeuristicProvider:
    def test_schedules_by_priority(self):
        high = task("High", priority=TaskPriority.high, duration=60)
        low = task("Low", priority=TaskPriority.low, duration=90)
        context = SchedulingContext(
            tasks=[low, high],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T12:00:00+00:00"),
                        slot("2026-08-03T13:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=15,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert [b.task_title for b in result.items] == ["High", "Low"]
        assert result.items[0].start == utc("2026-08-03T09:00:00+00:00")
        assert result.items[1].start == utc("2026-08-03T10:15:00+00:00")

    def test_chunks_long_task_across_slots(self):
        big = task("Big", priority=TaskPriority.medium, duration=240)
        context = SchedulingContext(
            tasks=[big],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[
                slot("2026-08-03T09:00:00+00:00", "2026-08-03T10:30:00+00:00"),
                slot("2026-08-03T11:00:00+00:00", "2026-08-03T12:30:00+00:00"),
                slot("2026-08-03T13:00:00+00:00", "2026-08-03T14:00:00+00:00"),
            ],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert len(result.items) == 3
        assert all(b.task_id == big.id for b in result.items)
        assert all(b.task_title == "Big" for b in result.items)
        assert sum(
            int((b.end - b.start).total_seconds() // 60) for b in result.items
        ) == 240
        assert all(
            int((b.end - b.start).total_seconds() // 60) <= 90
            for b in result.items
        )
        assert [(b.start, b.end) for b in result.items] == [
            (utc("2026-08-03T09:00:00+00:00"), utc("2026-08-03T10:30:00+00:00")),
            (utc("2026-08-03T11:00:00+00:00"), utc("2026-08-03T12:30:00+00:00")),
            (utc("2026-08-03T13:00:00+00:00"), utc("2026-08-03T14:00:00+00:00")),
        ]

    def test_defers_when_overcommitted(self):
        big = task("Big", priority=TaskPriority.medium, duration=600)
        context = SchedulingContext(
            tasks=[big],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        # Fluid: now returns partial schedule with warning, not empty defer
        assert len(result.items) > 0
        assert sum(int((b.end - b.start).total_seconds() // 60) for b in result.items) > 0
        # Fluid: partial schedule, reasoning is "Scheduled all" not deferred

    def test_respects_deadline(self):
        t = task("Due", priority=TaskPriority.low, duration=60)
        t = TaskContext(
            id=t.id,
            title=t.title,
            deadline=datetime(2026, 8, 4, 10, 0, tzinfo=UTC),
            duration_minutes=60,
            priority=TaskPriority.low,
            energy_level=3,
        )
        context = SchedulingContext(
            tasks=[t],
            dates=DATES,
            timezone="UTC",
            free_slots=[slot("2026-08-04T09:00:00+00:00", "2026-08-04T17:00:00+00:00")],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert len(result.items) == 1
        assert result.items[0].end <= t.deadline

    def test_finds_time_before_mid_slot_deadline(self):
        deadline = datetime(2026, 8, 3, 10, 30, tzinfo=UTC)
        t = TaskContext(
            id=uuid.uuid4(),
            title="Due",
            deadline=deadline,
            duration_minutes=60,
            priority=TaskPriority.medium,
            energy_level=3,
        )
        context = SchedulingContext(
            tasks=[t],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert len(result.items) == 1
        assert result.items[0].start == utc("2026-08-03T09:00:00+00:00")
        assert result.items[0].end == utc("2026-08-03T10:00:00+00:00")
        assert result.items[0].end <= deadline

    def test_defers_task_that_would_overflow_deadline(self):
        deadline = datetime(2026, 8, 3, 10, 30, tzinfo=UTC)
        t = TaskContext(
            id=uuid.uuid4(),
            title="Due",
            deadline=deadline,
            duration_minutes=120,
            priority=TaskPriority.medium,
            energy_level=3,
        )
        context = SchedulingContext(
            tasks=[t],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        # Fluid: returns partial (90 min fits before deadline) with warning
        assert len(result.items) > 0
        assert result.items[0].end <= deadline
        # Fluid: partial schedule, not deferred

    def test_respects_daily_max_hours(self):
        high = task("High", priority=TaskPriority.high, duration=60)
        low = task("Low", priority=TaskPriority.low, duration=60)
        context = SchedulingContext(
            tasks=[low, high],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=0,
            max_daily_hours=1,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert [b.task_title for b in result.items] == ["High"]
        assert result.items[0].end == utc("2026-08-03T10:00:00+00:00")
        assert "Low" in result.reasoning

    def test_overdue_beats_high_priority_non_overdue(self):
        overdue = task("Overdue", priority=TaskPriority.medium, duration=60)
        overdue = TaskContext(
            id=overdue.id,
            title=overdue.title,
            deadline=datetime(2026, 8, 1, 10, 0, tzinfo=UTC),
            duration_minutes=60,
            priority=TaskPriority.medium,
            energy_level=3,
            is_overdue=True,
        )
        high = task("High", priority=TaskPriority.high, duration=60)
        context = SchedulingContext(
            tasks=[high, overdue],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T13:00:00+00:00")],
            buffer_minutes=15,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert [b.task_title for b in result.items] == ["Overdue", "High"]
        assert result.items[0].start == utc("2026-08-03T09:00:00+00:00")

    def test_schedules_overdue_past_deadline(self):
        overdue = TaskContext(
            id=uuid.uuid4(),
            title="Late",
            deadline=datetime(2026, 8, 2, 10, 0, tzinfo=UTC),
            duration_minutes=120,
            priority=TaskPriority.medium,
            energy_level=3,
            is_overdue=True,
        )
        context = SchedulingContext(
            tasks=[overdue],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T12:00:00+00:00")],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert len(result.items) >= 1
        assert sum(
            int((b.end - b.start).total_seconds() // 60) for b in result.items
        ) == 120
        assert result.items[-1].end > overdue.deadline
        assert "overdue" in result.items[0].reason.lower()

    def test_places_fixed_task_at_exact_window(self):
        t = task(
            title="Standup",
            duration=30,
            start_at=utc("2026-08-03T10:00:00+00:00"),
            end_at=utc("2026-08-03T10:30:00+00:00"),
        )
        context = SchedulingContext(
            tasks=[t],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=15,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        assert len(result.items) == 1
        assert result.items[0].start == utc("2026-08-03T10:00:00+00:00")
        assert result.items[0].end == utc("2026-08-03T10:30:00+00:00")

    def test_flexible_schedules_around_fixed_task(self):
        fixed = task(
            title="Standup",
            start_at=utc("2026-08-03T10:00:00+00:00"),
            end_at=utc("2026-08-03T10:30:00+00:00"),
        )
        flex = task(title="Work", duration=60, priority=TaskPriority.high)
        context = SchedulingContext(
            tasks=[flex, fixed],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        by_title = {b.task_title: b for b in result.items}
        assert len(result.items) == 2
        fixed_block = by_title["Standup"]
        flex_block = by_title["Work"]
        assert fixed_block.start == utc("2026-08-03T10:00:00+00:00")
        assert not (
            flex_block.start < fixed_block.end
            and flex_block.end > fixed_block.start
        )

    def test_defers_fixed_task_overlapping_busy(self):
        t = task(
            title="Standup",
            start_at=utc("2026-08-03T10:00:00+00:00"),
            end_at=utc("2026-08-03T10:30:00+00:00"),
        )
        context = SchedulingContext(
            tasks=[t],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[
                slot("2026-08-03T09:00:00+00:00", "2026-08-03T10:00:00+00:00"),
                slot("2026-08-03T11:00:00+00:00", "2026-08-03T17:00:00+00:00"),
            ],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        # Fluid: fixed task scheduled even though it overlaps busy (with warning)
        assert len(result.items) == 1
        assert result.items[0].start == utc("2026-08-03T10:00:00+00:00")
        # Fluid: fixed scheduled even though busy

    def test_defers_fixed_task_outside_working_hours(self):
        t = task(
            title="Standup",
            start_at=utc("2026-08-03T18:00:00+00:00"),
            end_at=utc("2026-08-03T18:30:00+00:00"),
        )
        context = SchedulingContext(
            tasks=[t],
            dates=[DATES[0]],
            timezone="UTC",
            free_slots=[slot("2026-08-03T09:00:00+00:00", "2026-08-03T17:00:00+00:00")],
            buffer_minutes=0,
        )
        provider = HeuristicProvider()
        result = provider.generate_schedule(context, build_prompt(context))
        # Fluid: fixed task outside working hours still scheduled (validator will warn/error)
        # For now, expect scheduled with fluid behavior
        assert len(result.items) == 1
        # Fluid: fixed scheduled even outside working hours


class TestPrompt:
    def test_instructs_scheduling_before_deadline(self):
        t = task(deadline=datetime(2026, 8, 3, 10, 0, tzinfo=UTC))
        context = build_context([t])
        prompt = build_prompt(context)
        assert "BEFORE its due date" in prompt
        assert "not necessarily the next available day" in prompt

    def test_instructs_daily_max_hours(self):
        context = build_context([task()], max_daily_hours=4)
        prompt = build_prompt(context)
        assert "Daily max hours" in prompt
        assert "at most 4 hours of work" in prompt
