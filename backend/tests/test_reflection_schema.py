import uuid
from datetime import date, datetime, timezone

from app.schemas.reflection import ReflectionAnalysisResponse, ReflectionResponse


def _uid() -> uuid.UUID:
    return uuid.uuid4()


def test_reflection_response_serializes_date_only() -> None:
    payload = ReflectionResponse(
        id=_uid(),
        user_id=_uid(),
        date=date(2026, 9, 22),
        text="hello",
        analysis=None,
        created_at=datetime(2026, 9, 22, 1, 2, 3, tzinfo=timezone.utc),
        updated_at=datetime(2026, 9, 22, 1, 2, 3, tzinfo=timezone.utc),
    )
    body = payload.model_dump_json()
    assert '"date":"2026-09-22"' in body
    assert '"2026-09-22T00:00:00"' not in body


def test_analysis_response_includes_user_and_date_only() -> None:
    payload = ReflectionAnalysisResponse(
        id=_uid(),
        user_id=_uid(),
        date=date(2026, 9, 22),
        analysis="strong flow",
    )
    body = payload.model_dump_json()
    assert '"user_id"' in body
    assert '"date":"2026-09-22"' in body