import uuid
from datetime import datetime
from datetime import timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.task import Task
from app.repositories import calendar_block_repository
from app.schemas.calendar import CalendarBlockCreate
from app.schemas.calendar import CalendarBlockUpdate
from app.services.task_service import recompute_task_progress


class CalendarBlockNotFoundError(Exception):
    pass


class TaskNotFoundError(Exception):
    pass


class InvalidCalendarBlockError(Exception):
    pass


def _utc() -> ZoneInfo:
    return ZoneInfo("UTC")


class CalendarBlockService:
    def __init__(self, db: Session, user_id: uuid.UUID):
        self.db = db
        self.user_id = user_id

    def list_blocks(self, since: datetime | None = None):
        return calendar_block_repository.list_blocks(
            self.db, user_id=self.user_id, since=since
        )

    def get_block(self, block_id: uuid.UUID):
        block = calendar_block_repository.get_block(
            self.db, user_id=self.user_id, block_id=block_id
        )
        if block is None:
            raise CalendarBlockNotFoundError("Calendar block not found")
        return block

    def create_block(self, data: CalendarBlockCreate):
        if data.start_at >= data.end_at:
            raise InvalidCalendarBlockError(
                "Block end must be after block start"
            )
        task = self.db.scalar(
            select(Task).where(
                Task.id == data.task_id, Task.user_id == self.user_id
            )
        )
        if task is None:
            raise TaskNotFoundError("Task not found")
        block = calendar_block_repository.create_block(
            self.db, user_id=self.user_id, data=data
        )
        recompute_task_progress(self.db, task.id)
        self.db.commit()
        self.db.refresh(block)
        return block

    def update_block(self, block_id: uuid.UUID, data: CalendarBlockUpdate):
        block = self.get_block(block_id)
        merged = block.__dict__.copy()
        for field, value in data.model_dump(exclude_unset=True).items():
            merged[field] = value
        if (
            merged.get("start_at") is not None
            and merged.get("end_at") is not None
            and merged["start_at"] >= merged["end_at"]
        ):
            raise InvalidCalendarBlockError(
                "Block end must be after block start"
            )
        block = calendar_block_repository.update_block(self.db, block, data)
        self.db.commit()
        self.db.refresh(block)
        return block

    def delete_block(self, block_id: uuid.UUID) -> None:
        block = self.get_block(block_id)
        task_id = block.task_id
        calendar_block_repository.delete_block(self.db, block)
        recompute_task_progress(self.db, task_id)
        self.db.commit()

    def complete_block(
        self, block_id: uuid.UUID, note: str | None = None
    ):
        block = self.get_block(block_id)
        now = datetime.now(_utc())
        finished_early = block.end_at is not None and block.end_at > now + timedelta(minutes=5)
        block.completed_at = now
        block.completion_note = (
            note.strip() if note and note.strip() else None
        )
        recompute_task_progress(self.db, block.task_id)
        self.db.commit()
        self.db.refresh(block)
        # Fluid: if finished early, free up extra time and request approval for new schedule
        if finished_early:
            try:
                from app.services.scheduling_service import SchedulingService

                svc = SchedulingService(self.db, self.user_id)
                svc.auto_regenerate(trigger="task finished early - freed up time")
            except Exception:
                pass
        return block

    def reopen_block(self, block_id: uuid.UUID):
        block = self.get_block(block_id)
        block.completed_at = None
        block.completion_note = None
        recompute_task_progress(self.db, block.task_id)
        self.db.commit()
        self.db.refresh(block)
        return block
