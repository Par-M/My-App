from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.notification import DeviceRegisterRequest
from app.schemas.notification import DeviceTokenResponse
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/devices", tags=["notifications"])


def _service(
    db: Session = Depends(get_db),
) -> NotificationService:
    return NotificationService(db)


@router.post("/register", response_model=DeviceTokenResponse)
def register_device(
    payload: DeviceRegisterRequest,
    current_user: User = Depends(get_current_user),
    service: NotificationService = Depends(_service),
) -> DeviceTokenResponse:
    return service.register_device(current_user.id, payload)


@router.delete("/{device_id}")
def unregister_device(
    device_id: str,
    current_user: User = Depends(get_current_user),
    service: NotificationService = Depends(_service),
) -> dict:
    removed = service.unregister_device(current_user.id, device_id)
    if not removed:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found",
        )
    return {"message": "Device unregistered"}
