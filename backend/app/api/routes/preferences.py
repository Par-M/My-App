from fastapi import APIRouter
from fastapi import Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.preference import UserPreferenceResponse
from app.schemas.preference import UserPreferenceUpdate
from app.services.preference_service import PreferenceService

router = APIRouter(prefix="/preferences", tags=["preferences"])


def _service(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PreferenceService:
    return PreferenceService(db, current_user.id)


@router.get("", response_model=UserPreferenceResponse)
def get_preferences(
    service: PreferenceService = Depends(_service),
) -> UserPreferenceResponse:
    return service.get()


@router.put("", response_model=UserPreferenceResponse)
def update_preferences(
    payload: UserPreferenceUpdate,
    service: PreferenceService = Depends(_service),
) -> UserPreferenceResponse:
    return service.update(payload)
