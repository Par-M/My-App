import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.device_token import DeviceToken
from app.schemas.notification import DeviceRegisterRequest


def get_device(
    db: Session, *, user_id: uuid.UUID, device_id: str
) -> DeviceToken | None:
    return db.scalar(
        select(DeviceToken).where(
            DeviceToken.user_id == user_id,
            DeviceToken.device_id == device_id,
        )
    )


def upsert_device(
    db: Session, *, user_id: uuid.UUID, data: DeviceRegisterRequest
) -> DeviceToken:
    device = get_device(db, user_id=user_id, device_id=data.device_id)
    if device is None:
        device = DeviceToken(
            user_id=user_id,
            device_id=data.device_id,
            token=data.token,
            platform=data.platform,
            timezone=data.timezone,
        )
        db.add(device)
    else:
        device.token = data.token
        device.platform = data.platform
        device.timezone = data.timezone
        device.is_active = True
    db.flush()
    db.refresh(device)
    return device


def list_active_tokens(
    db: Session, *, user_id: uuid.UUID
) -> list[DeviceToken]:
    return list(
        db.scalars(
            select(DeviceToken).where(
                DeviceToken.user_id == user_id,
                DeviceToken.is_active.is_(True),
            )
        ).all()
    )


def deactivate_device(
    db: Session, *, user_id: uuid.UUID, device_id: str
) -> bool:
    device = get_device(db, user_id=user_id, device_id=device_id)
    if device is None or not device.is_active:
        return False
    device.is_active = False
    db.flush()
    return True


def user_timezone(db: Session, *, user_id: uuid.UUID) -> str | None:
    device = db.scalar(
        select(DeviceToken)
        .where(
            DeviceToken.user_id == user_id,
            DeviceToken.is_active.is_(True),
        )
        .order_by(DeviceToken.updated_at.desc())
        .limit(1)
    )
    if device is None:
        return None
    return device.timezone or "UTC"
