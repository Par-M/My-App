import uuid
from datetime import datetime

from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import Query
from fastapi import status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.task import TaskPriority
from app.models.task import TaskStatus
from app.models.user import User
from app.schemas.task import CompleteTaskRequest
from app.schemas.task import RescheduleRequest
from app.schemas.task import RescheduleResponse
from app.schemas.task import SnoozeRequest
from app.schemas.task import SnoozeResponse
from app.schemas.task import TaskCreate
from app.schemas.task import TaskListResponse
from app.schemas.task import TaskResponse
from app.schemas.task import TaskUpdate
from app.services.task_service import InvalidSortError
from app.services.task_service import InvalidTaskTransitionError
from app.services.task_service import TaskNotFoundError
from app.services.task_service import TaskService

router = APIRouter(prefix="/tasks", tags=["tasks"])


def _service(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TaskService:
    return TaskService(db, current_user.id)


def _handle_service_errors(exc: Exception) -> None:
    if isinstance(exc, TaskNotFoundError):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        )
    if isinstance(exc, InvalidTaskTransitionError):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        )
    if isinstance(exc, InvalidSortError):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        )
    raise exc


@router.post(
    "",
    response_model=TaskResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_task(
    payload: TaskCreate,
    service: TaskService = Depends(_service),
) -> TaskResponse:
    return service.create_task(payload)


@router.get("", response_model=TaskListResponse)
def list_tasks(
    search: str | None = Query(default=None, max_length=255),
    priority: TaskPriority | None = Query(default=None),
    status_filter: TaskStatus | None = Query(default=None, alias="status"),
    category: str | None = Query(default=None, max_length=100),
    archived: bool = Query(default=False),
    sort: str | None = Query(default=None),
    order: str = Query(default="asc", pattern="^(asc|desc)$"),
    since: datetime | None = Query(default=None),
    service: TaskService = Depends(_service),
) -> TaskListResponse:
    try:
        tasks = service.list_tasks(
            search=search,
            priority=priority,
            status=status_filter,
            category=category,
            archived=archived,
            sort=sort,
            order=order,
            since=since,
        )
    except (InvalidSortError, ValueError) as exc:
        _handle_service_errors(exc)
    return TaskListResponse(items=tasks, total=len(tasks))


@router.get("/overdue", response_model=TaskListResponse)
def list_overdue(
    service: TaskService = Depends(_service),
) -> TaskListResponse:
    tasks = service.list_overdue()
    return TaskListResponse(items=tasks, total=len(tasks))


@router.get("/{task_id}", response_model=TaskResponse)
def get_task(
    task_id: uuid.UUID,
    service: TaskService = Depends(_service),
) -> TaskResponse:
    try:
        return service.get_task(task_id)
    except TaskNotFoundError as exc:
        _handle_service_errors(exc)


@router.patch("/{task_id}", response_model=TaskResponse)
def update_task(
    task_id: uuid.UUID,
    payload: TaskUpdate,
    service: TaskService = Depends(_service),
) -> TaskResponse:
    try:
        return service.update_task(task_id, payload)
    except (TaskNotFoundError, InvalidTaskTransitionError) as exc:
        _handle_service_errors(exc)


@router.delete("/{task_id}")
def delete_task(
    task_id: uuid.UUID,
    service: TaskService = Depends(_service),
) -> dict[str, str]:
    try:
        service.delete_task(task_id)
    except TaskNotFoundError as exc:
        _handle_service_errors(exc)
    return {"message": "Task deleted"}


@router.post("/{task_id}/archive", response_model=TaskResponse)
def archive_task(
    task_id: uuid.UUID,
    service: TaskService = Depends(_service),
) -> TaskResponse:
    try:
        return service.archive_task(task_id)
    except TaskNotFoundError as exc:
        _handle_service_errors(exc)


@router.post("/{task_id}/restore", response_model=TaskResponse)
def restore_task(
    task_id: uuid.UUID,
    service: TaskService = Depends(_service),
) -> TaskResponse:
    try:
        return service.restore_task(task_id)
    except TaskNotFoundError as exc:
        _handle_service_errors(exc)


@router.post("/{task_id}/start", response_model=TaskResponse)
def start_task(
    task_id: uuid.UUID,
    service: TaskService = Depends(_service),
) -> TaskResponse:
    try:
        return service.start_task(task_id)
    except (TaskNotFoundError, InvalidTaskTransitionError) as exc:
        _handle_service_errors(exc)


@router.post("/{task_id}/complete", response_model=TaskResponse)
def complete_task(
    task_id: uuid.UUID,
    payload: CompleteTaskRequest,
    service: TaskService = Depends(_service),
) -> TaskResponse:
    try:
        return service.complete_task(
            task_id, payload.actual_minutes, payload.productivity
        )
    except TaskNotFoundError as exc:
        _handle_service_errors(exc)


@router.post("/{task_id}/snooze", response_model=SnoozeResponse)
def snooze_task(
    task_id: uuid.UUID,
    payload: SnoozeRequest,
    service: TaskService = Depends(_service),
) -> SnoozeResponse:
    try:
        task, blocks = service.snooze_task(
            task_id, payload.minutes, payload.timezone
        )
    except (TaskNotFoundError, InvalidTaskTransitionError) as exc:
        _handle_service_errors(exc)
    return SnoozeResponse(task=task, blocks=blocks)


@router.post("/{task_id}/reschedule", response_model=RescheduleResponse)
def reschedule_task(
    task_id: uuid.UUID,
    payload: RescheduleRequest,
    service: TaskService = Depends(_service),
) -> RescheduleResponse:
    try:
        task, blocks = service.reschedule_task(
            task_id,
            payload.minutes_remaining,
            payload.reason,
            payload.timezone,
        )
    except (TaskNotFoundError, InvalidTaskTransitionError) as exc:
        _handle_service_errors(exc)
    return RescheduleResponse(task=task, blocks=blocks)
