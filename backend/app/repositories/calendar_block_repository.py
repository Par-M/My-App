import uuid
from datetime import datetime

from sqlalchemy import Select
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.calendar_block import CalendarBlock
from app.schemas.calendar import CalendarBlockCreate
from app.schemas.calendar import CalendarBlockUpdate


def base_query(user_id: uuid.UUID) -> Select:
    return select(CalendarBlock).where(CalendarBlock.user_id == user_id)


def list_blocks(
    db: Session, *, user_id: uuid.UUID, since: datetime | None = None
) -> list[CalendarBlock]:
    statement = base_query(user_id).order_by(CalendarBlock.start_at)
    if since is not None:
        statement = statement.where(CalendarBlock.updated_at >= since)
    return list(db.scalars(statement).all())


def get_block(
    db: Session, *, user_id: uuid.UUID, block_id: uuid.UUID
) -> CalendarBlock | None:
    return db.scalar(
        base_query(user_id).where(CalendarBlock.id == block_id)
    )


def create_block(
    db: Session, *, user_id: uuid.UUID, data: CalendarBlockCreate
) -> CalendarBlock:
    block = CalendarBlock(user_id=user_id, **data.model_dump())
    db.add(block)
    db.flush()
    db.refresh(block)
    return block


def update_block(
    db: Session, block: CalendarBlock, data: CalendarBlockUpdate
) -> CalendarBlock:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(block, field, value)
    db.flush()
    db.refresh(block)
    return block


def delete_block(db: Session, block: CalendarBlock) -> None:
    db.delete(block)
    db.flush()
