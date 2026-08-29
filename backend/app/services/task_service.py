import uuid
from datetime import datetime
from datetime import timedelta
from datetime import time as dt_time
from zoneinfo import ZoneInfo

from sqlalchemy import func
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.calendar_block import CalendarBlock
from app.models.task import Task
from app.models.task import TaskStatus
from app.models.task_miss import TaskMiss
from app.repositories import task_repository
from app.repositories.task_repository import SORT_FIELDS
from app.schemas.task import TaskCreate
from app.schemas.task import TaskUpdate


class TaskNotFoundError(Exception):
    pass


class InvalidSortError(Exception):
    pass


class InvalidTaskTransitionError(Exception):
    pass


def _utc() -> ZoneInfo:
    return ZoneInfo("UTC")


def recompute_task_progress(db: Session, task_id: uuid.UUID) -> None:
    db.flush()
    total = db.scalar(
        select(func.count())
        .select_from(CalendarBlock)
        .where(CalendarBlock.task_id == task_id)
    )
    completed = db.scalar(
        select(func.count())
        .select_from(CalendarBlock)
        .where(
            CalendarBlock.task_id == task_id,
            CalendarBlock.completed_at.is_not(None),
        )
    )
    task = db.get(Task, task_id)
    if task is None:
        return
    if total and total > 0 and completed == total:
        if task.status != TaskStatus.completed:
            task.status = TaskStatus.completed
            task.completed_at = datetime.now(_utc())
        task.progress_percent = 100
    elif task.status == TaskStatus.completed and total and completed is not None and completed < total:
        # Reopened a block after completion - revert to pending
        task.status = TaskStatus.pending
        task.completed_at = None
        task.progress_percent = round((completed or 0) * 100 / total) if total else 0
    elif task.status == TaskStatus.completed:
        task.progress_percent = 100
    elif total:
        task.progress_percent = round((completed or 0) * 100 / total)
    else:
        task.progress_percent = 0
    db.flush()


class TaskService:
    def __init__(self, db: Session, user_id: uuid.UUID):
        self.db = db
        self.user_id = user_id

    def list_tasks(
        self,
        *,
        search: str | None = None,
        priority=None,
        status=None,
        category: str | None = None,
        archived: bool = False,
        sort: str | None = None,
        order: str = "asc",
        since: datetime | None = None,
    ) -> list[Task]:
        if order not in {"asc", "desc"}:
            raise InvalidSortError("order must be 'asc' or 'desc'")
        if sort is not None and sort not in SORT_FIELDS:
            raise InvalidSortError(
                f"sort must be one of {', '.join(sorted(SORT_FIELDS))}"
            )
        return task_repository.list_tasks(
            self.db,
            user_id=self.user_id,
            search=search,
            priority=priority,
            status=status,
            category=category,
            archived=archived,
            sort=sort,
            order=order,
            since=since,
        )

    def get_task(self, task_id: uuid.UUID) -> Task:
        task = task_repository.get_task(
            self.db, user_id=self.user_id, task_id=task_id
        )
        if task is None:
            raise TaskNotFoundError("Task not found")
        return task

    def create_task(self, data: TaskCreate) -> Task:
        task = task_repository.create_task(
            self.db, user_id=self.user_id, data=data
        )
        self.db.commit()
        self.db.refresh(task)
        # Fluid: if fixed event added last-minute, auto-regenerate and request approval
        if task.start_at is not None and task.end_at is not None:
            try:
                from app.services.scheduling_service import SchedulingService

                svc = SchedulingService(self.db, self.user_id)
                svc.auto_regenerate(trigger=f"fixed event '{task.title}' added")
            except Exception:
                pass
        return task

    def update_task(self, task_id: uuid.UUID, data: TaskUpdate) -> Task:
        task = self.get_task(task_id)
        start_at = (
            data.start_at
            if data.start_at is not None
            else task.start_at
        )
        end_at = data.end_at if data.end_at is not None else task.end_at
        if start_at is not None and end_at is not None and end_at <= start_at:
            raise InvalidTaskTransitionError(
                "end_at must be after start_at"
            )
        task = task_repository.update_task(self.db, task, data)
        if data.status is not None:
            if task.status == TaskStatus.completed:
                # Carry over to calendar view: mark pending blocks completed
                pending_blocks = list(
                    self.db.scalars(
                        select(CalendarBlock).where(
                            CalendarBlock.task_id == task.id,
                            CalendarBlock.completed_at.is_(None),
                        )
                    ).all()
                )
                now_ts = datetime.now(_utc())
                for blk in pending_blocks:
                    blk.completed_at = now_ts
                task.progress_percent = 100
                self.db.flush()
                # Auto-regen after marking complete
                try:
                    from app.services.scheduling_service import SchedulingService

                    svc = SchedulingService(self.db, self.user_id)
                    svc.auto_regenerate(trigger=f"task '{task.title}' marked complete")
                except Exception:
                    pass
            else:
                recompute_task_progress(self.db, task.id)
        self.db.commit()
        self.db.refresh(task)
        return task

    def delete_task(self, task_id: uuid.UUID) -> None:
        task = self.get_task(task_id)
        title = task.title
        task_repository.delete_task(self.db, task)
        self.db.commit()
        # Fluid: fixed or any event deleted - auto-regenerate and request approval
        try:
            from app.services.scheduling_service import SchedulingService

            svc = SchedulingService(self.db, self.user_id)
            svc.auto_regenerate(trigger=f"task '{title}' deleted")
        except Exception:
            pass

    def archive_task(self, task_id: uuid.UUID) -> Task:
        task = self.get_task(task_id)
        task = task_repository.set_archived(self.db, task, True)
        self.db.commit()
        self.db.refresh(task)
        return task

    def restore_task(self, task_id: uuid.UUID) -> Task:
        task = self.get_task(task_id)
        task = task_repository.set_archived(self.db, task, False)
        self.db.commit()
        self.db.refresh(task)
        return task

    def start_task(self, task_id: uuid.UUID) -> Task:
        task = self.get_task(task_id)
        if task.status == TaskStatus.completed:
            raise InvalidTaskTransitionError(
                "A completed task cannot be started"
            )
        task.status = TaskStatus.in_progress
        if task.started_at is None:
            task.started_at = datetime.now(_utc())
        self.db.commit()
        self.db.refresh(task)
        return task

    def complete_task(
        self,
        task_id: uuid.UUID,
        actual_minutes: int | None = None,
        productivity=None,
    ) -> Task:
        task = self.get_task(task_id)
        if task.status == TaskStatus.completed:
            self.db.refresh(task)
            return task
        task.status = TaskStatus.completed
        task.completed_at = datetime.now(_utc())
        if productivity is not None:
            task.productivity = productivity
        if actual_minutes is not None:
            task.actual_duration = (task.actual_duration or 0) + actual_minutes
        elif task.actual_duration is None:
            if task.started_at is not None:
                elapsed = (
                    datetime.now(_utc()) - task.started_at
                ).total_seconds() / 60
                task.actual_duration = int(max(1, round(elapsed)))
            else:
                task.actual_duration = 0
        # Carry over to calendar view: mark all pending blocks as completed
        pending_blocks = list(
            self.db.scalars(
                select(CalendarBlock).where(
                    CalendarBlock.task_id == task.id,
                    CalendarBlock.completed_at.is_(None),
                )
            ).all()
        )
        now_ts = datetime.now(_utc())
        for blk in pending_blocks:
            blk.completed_at = now_ts
        task.progress_percent = 100
        self.db.commit()
        self.db.refresh(task)
        for blk in pending_blocks:
            self.db.refresh(blk)
        # Fluid: task finished (maybe early) - free up time and request approval for new schedule
        try:
            from app.services.scheduling_service import SchedulingService

            svc = SchedulingService(self.db, self.user_id)
            svc.auto_regenerate(trigger=f"task '{task.title}' marked complete")
        except Exception:
            pass
        return task

    def list_overdue(self) -> list[Task]:
        now = datetime.now(_utc())
        deadline_ids = {
            task.id
            for task in self.db.scalars(
                select(Task).where(
                    Task.user_id == self.user_id,
                    Task.is_archived.is_(False),
                    Task.status != TaskStatus.completed,
                    Task.deadline.is_not(None),
                    Task.deadline < now,
                )
            ).all()
        }
        block_behind_ids = {
            block.task_id
            for block in self.db.scalars(
                select(CalendarBlock).where(
                    CalendarBlock.user_id == self.user_id,
                    CalendarBlock.completed_at.is_(None),
                    CalendarBlock.end_at < now,
                )
            ).all()
        }
        # A task whose due date is still in the future is not overdue even if
        # an older scheduled block already passed. Extending the deadline (or
        # rescheduling) clears it from the overdue list.
        future_deadline_ids = {
            task.id
            for task in self.db.scalars(
                select(Task).where(
                    Task.user_id == self.user_id,
                    Task.deadline.is_not(None),
                    Task.deadline >= now,
                )
            ).all()
        }
        block_behind_ids -= future_deadline_ids
        task_ids = deadline_ids | block_behind_ids
        if not task_ids:
            return []
        tasks = list(
            self.db.scalars(
                select(Task).where(
                    Task.user_id == self.user_id,
                    Task.is_archived.is_(False),
                    Task.status != TaskStatus.completed,
                    Task.id.in_(task_ids),
                )
            ).all()
        )
        tasks.sort(
            key=lambda t: (
                t.deadline is None,
                t.deadline or now + timedelta(days=3650),
            )
        )
        return tasks

    def reschedule_task(
        self,
        task_id: uuid.UUID,
        minutes_remaining: int,
        reason: str | None = None,
        timezone_name: str = "UTC",
    ) -> tuple[Task, list[CalendarBlock]]:
        task = self.get_task(task_id)
        if task.status == TaskStatus.completed:
            raise InvalidTaskTransitionError(
                "A completed task cannot be rescheduled"
            )

        tz = ZoneInfo(timezone_name)
        now = datetime.now(tz)
        old_deadline = task.deadline
        new_deadline = now + timedelta(minutes=minutes_remaining)

        task.deadline = new_deadline
        task.estimated_duration = minutes_remaining
        self.db.flush()

        blocks = list(
            self.db.scalars(
                select(CalendarBlock)
                .where(
                    CalendarBlock.task_id == task.id,
                    CalendarBlock.user_id == self.user_id,
                )
                .order_by(CalendarBlock.start_at)
            ).all()
        )

        pending_blocks = [
            block for block in blocks if block.completed_at is None
        ]
        total_duration = sum(
            int((block.end_at - block.start_at).total_seconds() / 60)
            for block in pending_blocks
        )
        scale = (
            min(1.0, minutes_remaining / total_duration)
            if total_duration
            else 0.0
        )
        cursor = now
        for block in pending_blocks:
            if not total_duration:
                self.db.delete(block)
                continue
            duration = max(
                1,
                int(
                    round(
                        (block.end_at - block.start_at).total_seconds()
                        / 60
                        * scale
                    )
                ),
            )
            block.start_at = cursor
            block.end_at = cursor + timedelta(minutes=duration)
            cursor = block.end_at

        miss = TaskMiss(
            user_id=self.user_id,
            task_id=task.id,
            task_title=task.title,
            category=task.category,
            missed_deadline=old_deadline,
            reason=reason.strip() if reason else None,
            minutes_remaining=minutes_remaining,
            rescheduled_to=new_deadline,
            created_at=datetime.now(_utc()),
        )
        self.db.add(miss)

        self.db.commit()
        self.db.refresh(task)

        blocks = list(
            self.db.scalars(
                select(CalendarBlock)
                .where(
                    CalendarBlock.task_id == task.id,
                    CalendarBlock.user_id == self.user_id,
                )
                .order_by(CalendarBlock.start_at)
            ).all()
        )
        return task, blocks

    def snooze_task(
        self,
        task_id: uuid.UUID,
        minutes: int,
        timezone_name: str = "UTC",
    ) -> tuple[Task, list[CalendarBlock]]:
        task = self.get_task(task_id)
        if task.status == TaskStatus.completed:
            raise InvalidTaskTransitionError(
                "A completed task cannot be snoozed"
            )

        tz = ZoneInfo(timezone_name)
        now = datetime.now(tz)
        today_start = datetime.combine(now.date(), dt_time.min, tzinfo=tz)
        today_end = datetime.combine(now.date(), dt_time.max, tzinfo=tz)

        blocks = list(
            self.db.scalars(
                select(CalendarBlock)
                .where(
                    CalendarBlock.task_id == task.id,
                    CalendarBlock.user_id == self.user_id,
                    CalendarBlock.start_at > now,
                    CalendarBlock.start_at <= today_end,
                    CalendarBlock.start_at >= today_start,
                )
                .order_by(CalendarBlock.start_at)
            ).all()
        )

        if not blocks:
            self.db.refresh(task)
            return task, []

        for block in blocks:
            new_start = block.start_at + timedelta(minutes=minutes)
            new_end = block.end_at + timedelta(minutes=minutes)
            if new_end > today_end:
                duration = block.end_at - block.start_at
                new_end = today_end
                new_start = today_end - duration
                if new_start < today_start:
                    new_start = today_start
                    new_end = today_start
            block.start_at = new_start
            block.end_at = new_end

        self.db.commit()
        self.db.refresh(task)
        for block in blocks:
            self.db.refresh(block)
        return task, blocks
