import uuid

from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.calendar import CalendarBlockCreate
from app.schemas.calendar import CalendarBlockListResponse
from app.schemas.calendar import CalendarBlockResponse
from app.schemas.calendar import CalendarBlockUpdate
from app.services.calendar_block_service import CalendarBlockNotFoundError
from app.services.calendar_block_service import CalendarBlockService
from app.services.calendar_block_service import InvalidCalendarBlockError
from app.services.calendar_block_service import TaskNotFoundError

router = APIRouter(prefix="/calendar", tags=["calendar"])


def _service(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CalendarBlockService:
    return CalendarBlockService(db, current_user.id)


def _handle_service_errors(exc: Exception) -> None:
    if isinstance(exc, CalendarBlockNotFoundError):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        )
    if isinstance(exc, TaskNotFoundError):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        )
    if isinstance(exc, InvalidCalendarBlockError):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        )
    raise exc


@router.get("/blocks", response_model=CalendarBlockListResponse)
def list_blocks(
    service: CalendarBlockService = Depends(_service),
) -> CalendarBlockListResponse:
    blocks = service.list_blocks()
    return CalendarBlockListResponse(items=blocks, total=len(blocks))


@router.post(
    "/blocks",
    response_model=CalendarBlockResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_block(
    payload: CalendarBlockCreate,
    service: CalendarBlockService = Depends(_service),
) -> CalendarBlockResponse:
    try:
        return service.create_block(payload)
    except (CalendarBlockNotFoundError, TaskNotFoundError, InvalidCalendarBlockError) as exc:
        _handle_service_errors(exc)


@router.patch("/blocks/{block_id}", response_model=CalendarBlockResponse)
def update_block(
    block_id: uuid.UUID,
    payload: CalendarBlockUpdate,
    service: CalendarBlockService = Depends(_service),
) -> CalendarBlockResponse:
    try:
        return service.update_block(block_id, payload)
    except (CalendarBlockNotFoundError, InvalidCalendarBlockError) as exc:
        _handle_service_errors(exc)


@router.delete("/blocks/{block_id}")
def delete_block(
    block_id: uuid.UUID,
    service: CalendarBlockService = Depends(_service),
) -> dict[str, str]:
    try:
        service.delete_block(block_id)
    except CalendarBlockNotFoundError as exc:
        _handle_service_errors(exc)
    return {"message": "Calendar block deleted"}
