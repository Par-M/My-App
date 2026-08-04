import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.user_preference import UserPreference
from app.schemas.preference import UserPreferenceUpdate


def get_preference(
    db: Session, *, user_id: uuid.UUID
) -> UserPreference | None:
    return db.scalar(
        select(UserPreference).where(UserPreference.user_id == user_id)
    )


def create_preference(
    db: Session, *, user_id: uuid.UUID
) -> UserPreference:
    preference = UserPreference(user_id=user_id)
    db.add(preference)
    db.flush()
    db.refresh(preference)
    return preference


def update_preference(
    db: Session, preference: UserPreference, data: UserPreferenceUpdate
) -> UserPreference:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(preference, field, value)
    db.flush()
    db.refresh(preference)
    return preference
