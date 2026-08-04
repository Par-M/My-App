import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.notification_preference import NotificationPreference
from app.schemas.notification import NotificationPreferenceUpdate


def get_preference(
    db: Session, *, user_id: uuid.UUID
) -> NotificationPreference | None:
    return db.scalar(
        select(NotificationPreference).where(
            NotificationPreference.user_id == user_id
        )
    )


def create_preference(
    db: Session, *, user_id: uuid.UUID
) -> NotificationPreference:
    preference = NotificationPreference(user_id=user_id)
    db.add(preference)
    db.flush()
    db.refresh(preference)
    return preference


def update_preference(
    db: Session,
    preference: NotificationPreference,
    data: NotificationPreferenceUpdate,
) -> NotificationPreference:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(preference, field, value)
    db.flush()
    db.refresh(preference)
    return preference
