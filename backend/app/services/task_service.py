import uuid
from datetime import datetime
from datetime import timedelta
from datetime import time as dt_time
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.calendar_block import CalendarBlock
from app.models.task import Task
from app.models.task import TaskStatus
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
        return task

    def update_task(self, task_id: uuid.UUID, data: TaskUpdate) -> Task:
        task = self.get_task(task_id)
        task = task_repository.update_task(self.db, task, data)
        self.db.commit()
        self.db.refresh(task)
        return task

    def delete_task(self, task_id: uuid.UUID) -> None:
        task = self.get_task(task_id)
        task_repository.delete_task(self.db, task)
        self.db.commit()

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
        self.db.commit()
        self.db.refresh(task)
        return task

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
