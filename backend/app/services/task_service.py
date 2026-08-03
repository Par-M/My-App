import uuid

from sqlalchemy.orm import Session

from app.models.task import Task
from app.repositories import task_repository
from app.repositories.task_repository import SORT_FIELDS
from app.schemas.task import TaskCreate
from app.schemas.task import TaskUpdate


class TaskNotFoundError(Exception):
    pass


class InvalidSortError(Exception):
    pass


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
