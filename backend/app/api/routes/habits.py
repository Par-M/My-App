import uuid
from datetime import date
from zoneinfo import ZoneInfo

from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import Query
from fastapi import status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.habit import HabitCreate
from app.schemas.habit import HabitDashboardResponse
from app.schemas.habit import HabitDaySet
from app.schemas.habit import HabitDaySetResponse
from app.schemas.habit import HabitListResponse
from app.schemas.habit import HabitLogCreate
from app.schemas.habit import HabitLogResponse
from app.schemas.habit import HabitResponse
from app.schemas.habit import HabitUpdate
from app.services.habit_service import HabitNotFoundError
from app.services.habit_service import HabitService

router = APIRouter(prefix="/habits", tags=["habits"])


def _service(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> HabitService:
    return HabitService(db, current_user.id)


def _handle_not_found(exc: HabitNotFoundError) -> None:
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail=str(exc),
    )


@router.get("/dashboard", response_model=HabitDashboardResponse)
def dashboard(
    timezone: str = Query(default="UTC"),
    service: HabitService = Depends(_service),
) -> HabitDashboardResponse:
    try:
        ZoneInfo(timezone)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"Invalid IANA timezone: {timezone}",
        ) from exc
    return HabitDashboardResponse(habits=service.dashboard(timezone))


@router.post(
    "",
    response_model=HabitResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_habit(
    payload: HabitCreate,
    service: HabitService = Depends(_service),
) -> HabitResponse:
    return service.create_habit(payload)


@router.get("", response_model=HabitListResponse)
def list_habits(
    service: HabitService = Depends(_service),
) -> HabitListResponse:
    habits = service.list_habits()
    return HabitListResponse(items=habits, total=len(habits))


@router.patch("/{habit_id}", response_model=HabitResponse)
def update_habit(
    habit_id: uuid.UUID,
    payload: HabitUpdate,
    service: HabitService = Depends(_service),
) -> HabitResponse:
    try:
        return service.update_habit(habit_id, payload)
    except HabitNotFoundError as exc:
        _handle_not_found(exc)


@router.delete("/{habit_id}")
def delete_habit(
    habit_id: uuid.UUID,
    service: HabitService = Depends(_service),
) -> dict[str, str]:
    try:
        service.delete_habit(habit_id)
    except HabitNotFoundError as exc:
        _handle_not_found(exc)
    return {"message": "Habit deleted"}


@router.post(
    "/{habit_id}/logs",
    response_model=HabitLogResponse,
    status_code=status.HTTP_201_CREATED,
)
def log_completion(
    habit_id: uuid.UUID,
    payload: HabitLogCreate,
    service: HabitService = Depends(_service),
) -> HabitLogResponse:
    try:
        return service.log_completion(habit_id, payload.count, payload.date)
    except HabitNotFoundError as exc:
        _handle_not_found(exc)


@router.put("/{habit_id}/logs/day", response_model=HabitDaySetResponse)
def set_day_count(
    habit_id: uuid.UUID,
    payload: HabitDaySet,
    timezone: str = Query(default="UTC"),
    service: HabitService = Depends(_service),
) -> HabitDaySetResponse:
    try:
        ZoneInfo(timezone)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"Invalid IANA timezone: {timezone}",
        ) from exc
    try:
        day, count = service.set_day_count(
            habit_id,
            payload.count,
            payload.date,
            timezone,
        )
    except HabitNotFoundError as exc:
        _handle_not_found(exc)
    return HabitDaySetResponse(habit_id=habit_id, date=day, count=count)
