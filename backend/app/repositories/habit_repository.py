import uuid
from datetime import datetime

from sqlalchemy import Select
from sqlalchemy import func
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.habit import Habit
from app.models.habit import HabitLog
from app.schemas.habit import HabitCreate
from app.schemas.habit import HabitUpdate


def _base_query(user_id: uuid.UUID) -> Select:
    return select(Habit).where(Habit.user_id == user_id)


def _for_next_position(db: Session, user_id: uuid.UUID) -> int:
    max_position = db.scalar(
        select(func.max(Habit.position)).where(Habit.user_id == user_id)
    )
    return (max_position or -1) + 1


def create_habit(db: Session, *, user_id: uuid.UUID, data: HabitCreate) -> Habit:
    habit = Habit(user_id=user_id, position=_for_next_position(db, user_id), **data.model_dump())
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
            _base_query(user_id).order_by(
                Habit.position, Habit.created_at, Habit.title
            )
        ).all()
    )


def reorder_habits(
    db: Session, *, user_id: uuid.UUID, habit_ids: list[uuid.UUID]
) -> list[Habit]:
    """Assign ascending positions to the given habits (in order) and return them.

    Only the provided habits are touched. Any habit id that does not belong to
    the user is simply skipped.
    """
    habits = {
        habit.id: habit
        for habit in db.scalars(
            _base_query(user_id).where(Habit.id.in_(habit_ids))
        ).all()
    }
    ordered: list[Habit] = []
    for index, habit_id in enumerate(habit_ids):
        habit = habits.get(habit_id)
        if habit is None:
            continue
        habit.position = index
        ordered.append(habit)
    db.flush()
    return ordered


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
