import uuid
from datetime import datetime

from sqlalchemy import Select
from sqlalchemy import case
from sqlalchemy import or_
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.task import Task
from app.models.task import TaskPriority
from app.models.task import TaskStatus
from app.schemas.task import TaskCreate
from app.schemas.task import TaskUpdate

PRIORITY_RANK = case(
    (Task.priority == TaskPriority.low, 0),
    (Task.priority == TaskPriority.medium, 1),
    (Task.priority == TaskPriority.high, 2),
    else_=1,
)

SORT_FIELDS = {
    "deadline": lambda order: (
        Task.deadline.asc().nulls_last()
        if order == "asc"
        else Task.deadline.desc().nulls_first()
    ),
    "priority": lambda order: (
        PRIORITY_RANK.asc()
        if order == "asc"
        else PRIORITY_RANK.desc()
    ),
    "created_at": lambda order: Task.created_at.asc()
    if order == "asc"
    else Task.created_at.desc(),
    "updated_at": lambda order: Task.updated_at.asc()
    if order == "asc"
    else Task.updated_at.desc(),
}


def _base_query(user_id: uuid.UUID) -> Select:
    return select(Task).where(Task.user_id == user_id)


def create_task(db: Session, *, user_id: uuid.UUID, data: TaskCreate) -> Task:
    task = Task(user_id=user_id, **data.model_dump())
    db.add(task)
    db.flush()
    db.refresh(task)
    return task


def get_task(db: Session, *, user_id: uuid.UUID, task_id: uuid.UUID) -> Task | None:
    return db.scalar(
        _base_query(user_id).where(Task.id == task_id)
    )


def search_tasks(
    db: Session, *, user_id: uuid.UUID, query: str
) -> Select:
    pattern = f"%{query.strip()}%"
    return _base_query(user_id).where(
        or_(
            Task.title.ilike(pattern),
            Task.description.ilike(pattern),
            Task.notes.ilike(pattern),
            Task.category.ilike(pattern),
        )
    )


def filter_tasks(
    db: Session,
    *,
    user_id: uuid.UUID,
    priority: TaskPriority | None = None,
    status: TaskStatus | None = None,
    category: str | None = None,
    archived: bool = False,
) -> Select:
    statement = _base_query(user_id)
    if priority is not None:
        statement = statement.where(Task.priority == priority)
    if status is not None:
        statement = statement.where(Task.status == status)
    if category is not None:
        statement = statement.where(Task.category == category)
    statement = statement.where(Task.is_archived.is_(archived))
    return statement


def list_tasks(
    db: Session,
    *,
    user_id: uuid.UUID,
    search: str | None = None,
    priority: TaskPriority | None = None,
    status: TaskStatus | None = None,
    category: str | None = None,
    archived: bool = False,
    sort: str | None = None,
    order: str = "asc",
    since: datetime | None = None,
) -> list[Task]:
    statement = filter_tasks(
        db,
        user_id=user_id,
        priority=priority,
        status=status,
        category=category,
        archived=archived,
    )
    if since is not None:
        statement = statement.where(Task.updated_at >= since)
    if search:
        statement = statement.where(
            or_(
                Task.title.ilike(f"%{search.strip()}%"),
                Task.description.ilike(f"%{search.strip()}%"),
                Task.notes.ilike(f"%{search.strip()}%"),
                Task.category.ilike(f"%{search.strip()}%"),
            )
        )
    if sort in SORT_FIELDS:
        statement = statement.order_by(
            SORT_FIELDS[sort](order), Task.created_at.desc()
        )
    else:
        statement = statement.order_by(Task.created_at.desc())
    return list(db.scalars(statement).all())


def update_task(db: Session, task: Task, data: TaskUpdate) -> Task:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(task, field, value)
    db.flush()
    db.refresh(task)
    return task


def set_archived(db: Session, task: Task, archived: bool) -> Task:
    task.is_archived = archived
    db.flush()
    db.refresh(task)
    return task


def delete_task(db: Session, task: Task) -> None:
    db.delete(task)
    db.flush()
