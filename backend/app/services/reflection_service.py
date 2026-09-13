import uuid
from datetime import datetime

from sqlalchemy.orm import Session

from app.repositories import reflection_repository
from app.schemas.reflection import ReflectionAnalysisResponse
from app.schemas.reflection import ReflectionCreate
from app.schemas.reflection import ReflectionResponse
from app.services.text_analysis import AnalysisResult
from app.services.text_analysis import TextAnalysisError
from app.services.text_analysis import default_analysis_provider


class ReflectionNotFoundError(Exception):
    pass


class ReflectionService:
    """Owns creating, listing, analyzing, and deleting reflections."""

    def __init__(self, db: Session, *, user_id: uuid.UUID) -> None:
        self.db = db
        self.user_id = user_id

    def create_reflection(
        self,
        data: ReflectionCreate,
        *,
        analyze: bool = False,
    ) -> ReflectionResponse:
        reflection = reflection_repository.create_reflection(
            self.db,
            user_id=self.user_id,
            data=data,
        )
        if analyze:
            reflection = self._analyze(reflection)
        self.db.commit()
        self.db.refresh(reflection)
        return ReflectionResponse.model_validate(reflection)

    def get_reflection(self, reflection_id: uuid.UUID) -> ReflectionResponse:
        reflection = reflection_repository.get_reflection(
            self.db,
            user_id=self.user_id,
            reflection_id=reflection_id,
        )
        if reflection is None:
            raise ReflectionNotFoundError("Reflection not found")
        return ReflectionResponse.model_validate(reflection)

    def list_reflections(
        self,
        *,
        after: datetime | None = None,
        before: datetime | None = None,
    ) -> list[ReflectionResponse]:
        reflections = reflection_repository.list_reflections(
            self.db,
            user_id=self.user_id,
            after=after,
            before=before,
        )
        return [ReflectionResponse.model_validate(r) for r in reflections]

    def analyze_reflection(self, reflection_id: uuid.UUID) -> ReflectionAnalysisResponse:
        reflection = reflection_repository.get_reflection(
            self.db,
            user_id=self.user_id,
            reflection_id=reflection_id,
        )
        if reflection is None:
            raise ReflectionNotFoundError("Reflection not found")
        reflection = self._analyze(reflection)
        self.db.commit()
        self.db.refresh(reflection)
        return ReflectionAnalysisResponse(
            id=reflection.id,
            date=reflection.date,
            analysis=reflection.analysis or "",
        )

    def delete_reflection(self, reflection_id: uuid.UUID) -> None:
        reflection = reflection_repository.get_reflection(
            self.db,
            user_id=self.user_id,
            reflection_id=reflection_id,
        )
        if reflection is None:
            raise ReflectionNotFoundError("Reflection not found")
        reflection_repository.delete_reflection(self.db, reflection)
        self.db.commit()

    def _analyze(self, reflection):
        analysis = self._analyze_text(reflection.text)
        return reflection_repository.update_reflection_analysis(
            self.db,
            reflection=reflection,
            analysis=analysis,
        )

    def _analyze_text(self, text: str) -> str:
        provider = default_analysis_provider()
        prompt = (
            f"Here is a user's end-of-day reflection:\n\n{text}\n\n"
            "Respond with one warm, practical insight (1-2 sentences) that "
            "names what went well and what to carry into tomorrow. Do not "
            "repeat the input."
        )
        try:
            result = provider.analyze_text(prompt)
        except TextAnalysisError:
            return self._fallback(text)
        insight = result.insight if isinstance(result, AnalysisResult) else str(result)
        return insight.strip()

    @staticmethod
    def _fallback(text: str) -> str:
        tokens = [t.strip(" .,!?") for t in text.split()]
        words = [t for t in tokens if t]
        if not words:
            return "Thanks for reflecting. Consider one sentence on what you'd protect tomorrow."
        return (
            f"You wrote '{' '.join(words[:12])}"
            + ("...' " if len(words) > 16 else "'. ")
            + "Naming it is the first step; protect the same slot tomorrow."
        )
