from fastapi import APIRouter
from fastapi import Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.notification import NotificationPreferenceResponse
from app.schemas.notification import NotificationPreferenceUpdate
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


def _service(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> NotificationService:
    return NotificationService(db, current_user.id)


@router.get("/preferences", response_model=NotificationPreferenceResponse)
def get_preferences(
    service: NotificationService = Depends(_service),
) -> NotificationPreferenceResponse:
    return service.get_preferences(service.user_id)


@router.patch("/preferences", response_model=NotificationPreferenceResponse)
def update_preferences(
    payload: NotificationPreferenceUpdate,
    service: NotificationService = Depends(_service),
) -> NotificationPreferenceResponse:
    return service.update_preferences(service.user_id, payload)
