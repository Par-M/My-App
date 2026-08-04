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
from app.schemas.planner import DailySummaryResponse
from app.schemas.planner import TodayResponse
from app.services.planner_service import PlannerService

router = APIRouter(tags=["planner"])


def _service(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PlannerService:
    return PlannerService(db, current_user.id)


def _validate_timezone(value: str) -> str:
    try:
        ZoneInfo(value)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"Invalid IANA timezone: {value}",
        ) from exc
    return value


@router.get("/today", response_model=TodayResponse)
def today(
    timezone: str = Query(default="UTC"),
    service: PlannerService = Depends(_service),
) -> TodayResponse:
    return service.today(_validate_timezone(timezone))


@router.get("/daily-summary", response_model=DailySummaryResponse)
def daily_summary(
    timezone: str = Query(default="UTC"),
    service: PlannerService = Depends(_service),
) -> DailySummaryResponse:
    return service.daily_summary(_validate_timezone(timezone))
