import uuid
from datetime import date

from sqlalchemy import Select
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.reflection import Reflection
from app.schemas.reflection import ReflectionCreate


def _base_query(user_id: uuid.UUID) -> Select:
    return select(Reflection).where(Reflection.user_id == user_id)


def _where_id(query: Select, reflection_id: uuid.UUID) -> Select:
    return query.where(Reflection.id == reflection_id)


def create_reflection(
    db: Session, *, user_id: uuid.UUID, data: ReflectionCreate
) -> Reflection:
    reflection = Reflection(
        user_id=user_id,
        date=data.date,
        text=data.text,
    )
    db.add(reflection)
    db.flush()
    db.refresh(reflection)
    return reflection


def get_reflection_by_id(
    db: Session, *, user_id: uuid.UUID, reflection_id: uuid.UUID
) -> Reflection | None:
    return db.scalar(_where_id(_base_query(user_id), reflection_id))


def list_reflections(
    db: Session,
    *,
    user_id: uuid.UUID,
    after: date | None = None,
    before: date | None = None,
) -> list[Reflection]:
    query = _base_query(user_id)
    if after is not None:
        query = query.where(Reflection.date >= after)
    if before is not None:
        query = query.where(Reflection.date <= before)
    return list(
        db.scalars(
            query.order_by(Reflection.date.desc())
        ).all()
    )


def update_reflection_analysis(
    db: Session, reflection: Reflection, *, analysis: str
) -> Reflection:
    reflection.analysis = analysis
    db.flush()
    db.refresh(reflection)
    return reflection


def delete_reflection(db: Session, reflection: Reflection) -> None:
    db.delete(reflection)
    db.flush()
