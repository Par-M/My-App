import uuid

from sqlalchemy.orm import Session

from app.models.user_preference import UserPreference
from app.repositories import preference_repository
from app.schemas.preference import UserPreferenceUpdate


class PreferenceService:
    def __init__(self, db: Session, user_id: uuid.UUID):
        self.db = db
        self.user_id = user_id

    def get(self) -> UserPreference:
        preference = preference_repository.get_preference(
            self.db, user_id=self.user_id
        )
        if preference is None:
            preference = preference_repository.create_preference(
                self.db, user_id=self.user_id
            )
            self.db.commit()
            self.db.refresh(preference)
        return preference

    def update(self, data: UserPreferenceUpdate) -> UserPreference:
        preference = self.get()
        preference = preference_repository.update_preference(
            self.db, preference, data
        )
        self.db.commit()
        self.db.refresh(preference)
        return preference
