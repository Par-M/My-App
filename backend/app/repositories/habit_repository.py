import uuid
from datetime import datetime

from sqlalchemy import Select
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.habit import Habit
from app.models.habit import HabitLog
from app.schemas.habit import HabitCreate
from app.schemas.habit import HabitUpdate


def _base_query(user_id: uuid.UUID) -> Select:
    return select(Habit).where(Habit.user_id == user_id)


def create_habit(db: Session, *, user_id: uuid.UUID, data: HabitCreate) -> Habit:
    habit = Habit(user_id=user_id, **data.model_dump())
    db.add(habit)
    db.flush()
    db.refresh(habit)
    return habit


def get_habit(
    db: Session, *, user_id: uuid.UUID, habit_id: uuid.UUID
) -> Habit | None:
    return db.scalar(_base_query(user_id).where(Habit.id == habit_id))


def list_habits(db: Session, *, user_id: uuid.UUID) -> list[Habit]:
    return list(
        db.scalars(
            _base_query(user_id).order_by(Habit.created_at, Habit.title)
        ).all()
    )


def update_habit(db: Session, habit: Habit, data: HabitUpdate) -> Habit:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(habit, field, value)
    db.flush()
    db.refresh(habit)
    return habit


def delete_habit(db: Session, habit: Habit) -> None:
    db.delete(habit)
    db.flush()


def add_log(
    db: Session,
    *,
    user_id: uuid.UUID,
    habit_id: uuid.UUID,
    count: int,
    completed_at: datetime,
) -> HabitLog:
    log = HabitLog(
        user_id=user_id,
        habit_id=habit_id,
        count=count,
        completed_at=completed_at,
    )
    db.add(log)
    db.flush()
    db.refresh(log)
    return log


def list_logs(db: Session, *, habit_id: uuid.UUID) -> list[HabitLog]:
    return list(
        db.scalars(
            select(HabitLog)
            .where(HabitLog.habit_id == habit_id)
            .order_by(HabitLog.completed_at)
        ).all()
    )
