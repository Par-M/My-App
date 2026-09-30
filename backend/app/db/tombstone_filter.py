"""Global tombstone filter.

Deleting a task or a calendar block tombstones the row instead of removing it,
because an incremental download has to be able to tell another device that a
record disappeared. A hard-deleted row is indistinguishable from one the other
device never downloaded.

That makes "not deleted" part of what a live record *is*, so rather than
remembering to add a filter at every call site, the criteria is applied to every
ORM statement. ``with_loader_criteria`` covers ``select()``, ``Session.get()``,
relationship loads and aggregate counts, which is the set of ways this codebase
reads these two models.

The sync service legitimately needs the tombstoned rows, so it opts out for the
duration of a lookup via :func:`including_deleted`.
"""

from contextlib import contextmanager
from contextvars import ContextVar

from sqlalchemy import event
from sqlalchemy.orm import Session
from sqlalchemy.orm import with_loader_criteria

from app.models.calendar_block import CalendarBlock
from app.models.task import Task

_see_deleted: ContextVar[bool] = ContextVar("see_deleted", default=False)


@contextmanager
def including_deleted():
    """Read tombstoned rows as well as live ones.

    Only the sync service should need this: it is the component responsible for
    reporting deletions and for resurrecting a record.
    """
    token = _see_deleted.set(True)
    try:
        yield
    finally:
        _see_deleted.reset(token)


def _hide_deleted(execute_state) -> None:
    if _see_deleted.get() or not execute_state.is_select:
        return
    execute_state.statement = execute_state.statement.options(
        with_loader_criteria(Task, Task.deleted_at.is_(None)),
        with_loader_criteria(CalendarBlock, CalendarBlock.deleted_at.is_(None)),
    )


def register(session_factory: type[Session]) -> None:
    event.listen(session_factory, "do_orm_execute", _hide_deleted)
