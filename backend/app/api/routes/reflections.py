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
from app.models.user import User
from app.schemas.reflection import MorningMessageResponse
from app.schemas.reflection import ReflectionAnalysisResponse
from app.schemas.reflection import ReflectionCreate
from app.schemas.reflection import ReflectionCreateDaily
from app.schemas.reflection import ReflectionResponse
from app.services.reflection_service import ReflectionNotFoundError
from app.services.reflection_service import ReflectionService

router = APIRouter(prefix="/reflections", tags=["reflections"])


def _service(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ReflectionService:
    return ReflectionService(db, user_id=current_user.id)


def _handle_not_found(exc: Exception) -> None:
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail=str(exc),
    ) from exc


@router.post(
    "",
    response_model=ReflectionResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_reflection(
    payload: ReflectionCreate,
    service: ReflectionService = Depends(_service),
) -> ReflectionResponse:
    return service.create_reflection(payload)


@router.post(
    "/daily",
    response_model=ReflectionResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_daily_reflection(
    payload: ReflectionCreateDaily,
    service: ReflectionService = Depends(_service),
) -> ReflectionResponse:
    return service.create_reflection(payload)


@router.get("", response_model=list[ReflectionResponse])
def list_reflections(
    after: datetime | None = Query(default=None),
    before: datetime | None = Query(default=None),
    service: ReflectionService = Depends(_service),
) -> list[ReflectionResponse]:
    return service.list_reflections(after=after, before=before)


@router.get("/morning-message", response_model=MorningMessageResponse)
def morning_message(
    service: ReflectionService = Depends(_service),
) -> MorningMessageResponse:
    return service.morning_message()


@router.get("/{reflection_id}", response_model=ReflectionResponse)
def get_reflection(
    reflection_id: uuid.UUID,
    service: ReflectionService = Depends(_service),
) -> ReflectionResponse:
    try:
        return service.get_reflection(reflection_id)
    except ReflectionNotFoundError as exc:
        _handle_not_found(exc)


@router.post(
    "/{reflection_id}/analysis",
    response_model=ReflectionAnalysisResponse,
)
def analyze_reflection(
    reflection_id: uuid.UUID,
    service: ReflectionService = Depends(_service),
) -> ReflectionAnalysisResponse:
    try:
        return service.analyze_reflection(reflection_id)
    except ReflectionNotFoundError as exc:
        _handle_not_found(exc)


@router.delete("/{reflection_id}")
def delete_reflection(
    reflection_id: uuid.UUID,
    service: ReflectionService = Depends(_service),
) -> dict[str, str]:
    try:
        service.delete_reflection(reflection_id)
    except ReflectionNotFoundError as exc:
        _handle_not_found(exc)
    return {"message": "Reflection deleted"}
