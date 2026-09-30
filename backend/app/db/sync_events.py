"""Change-log capture for replicated entities.

Tasks and calendar blocks are written from several places: the task
repositories, the calendar repository, the scheduling service when a proposal
is accepted, and the sync service itself. A pull-based replication protocol is
only correct if *every* write is recorded, so rather than instrumenting each
call site this module listens to the session's flush cycle.

The listener runs in two phases:

* ``before_flush`` increments ``revision`` on each modified row. It has to
  happen here because by ``after_flush`` the UPDATE has already been emitted.
* ``after_flush`` appends a ``sync_changes`` row per affected record, using a
  Core insert so the log entry joins the same transaction as the change. If the
  transaction rolls back, the log rolls back with it, so the log can never
  claim a change that did not happen.

``register`` is idempotent and is called once during app startup.
"""

from sqlalchemy import event
from sqlalchemy import insert
from sqlalchemy.orm import Session

from app.models.calendar_block import CalendarBlock
from app.models.sync_state import ENTITY_BLOCK
from app.models.sync_state import ENTITY_TASK
from app.models.sync_state import SyncChange
from app.models.task import Task

# entity type -> ORM class
SYNCED_MODELS: dict[str, type] = {
    ENTITY_TASK: Task,
    ENTITY_BLOCK: CalendarBlock,
}

_REGISTERED = False


def _increment_revisions(session: Session) -> None:
    for model in SYNCED_MODELS.values():
        for obj in session.dirty:
            if isinstance(obj, model):
                obj.revision = (obj.revision or 0) + 1


def _log_changes(session: Session) -> None:
    for entity, model in SYNCED_MODELS.items():
        for obj in session.new:
            if isinstance(obj, model):
                _append(session, entity, obj, "upsert")
        for obj in session.dirty:
            if isinstance(obj, model):
                _append(session, entity, obj, "upsert")
        for obj in session.deleted:
            if isinstance(obj, model):
                _append(session, entity, obj, "delete")


def _append(
    session: Session,
    entity: str,
    obj: object,
    operation: str,
) -> None:
    # A deleted object may have lost its loaded attributes if the delete
    # cascaded, so read the identifying values defensively.
    user_id = getattr(obj, "user_id", None)
    entity_id = getattr(obj, "id", None)
    if user_id is None or entity_id is None:
        return

    session.execute(
        insert(SyncChange.__table__).values(
            user_id=user_id,
            entity=entity,
            entity_id=entity_id,
            revision=getattr(obj, "revision", 1) or 1,
            operation=operation,
        )
    )


def register(session_factory) -> None:
    """Attach the flush listeners to a session factory, once."""
    global _REGISTERED
    if _REGISTERED:
        return

    @event.listens_for(session_factory, "before_flush")
    def _before_flush(session, flush_context, instances):  # noqa: ANN001
        _increment_revisions(session)

    @event.listens_for(session_factory, "after_flush")
    def _after_flush(session, flush_context):  # noqa: ANN001
        _log_changes(session)

    _REGISTERED = True
