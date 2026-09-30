from fastapi import APIRouter
from fastapi import Depends
from fastapi import HTTPException
from fastapi import Query
from fastapi import status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.sync import DEFAULT_PULL_LIMIT
from app.schemas.sync import MAX_PULL_LIMIT
from app.schemas.sync import PullResponse
from app.schemas.sync import PushRequest
from app.schemas.sync import PushResponse
from app.services.sync_service import SyncError
from app.services.sync_service import SyncService

router = APIRouter(prefix="/sync", tags=["Sync"])


@router.get("/pull", response_model=PullResponse)
def pull_changes(
    cursor: int = Query(
        default=0,
        ge=0,
        description="Last server sequence number this device applied.",
    ),
    limit: int = Query(default=DEFAULT_PULL_LIMIT, ge=1, le=MAX_PULL_LIMIT),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PullResponse:
    """Return every change after ``cursor``, tombstones included.

    This is the replication endpoint. It is intentionally not the task list
    endpoint: that one is filtered by archive state, priority, category and
    search, so asking it for "everything" by passing ``archived=true`` returned
    only archived tasks and caused a client to purge its active ones.
    """
    return SyncService(db, current_user.id).pull(cursor=cursor, limit=limit)


@router.post("/push", response_model=PushResponse)
def push_changes(
    request: PushRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PushResponse:
    """Apply a batch of client operations.

    Each operation carries a client-generated ``operation_id``. Pushing the
    same id twice replays the original result instead of applying the change
    again, so a lost response can be retried safely.
    """
    try:
        return SyncService(db, current_user.id).push(request.operations)
    except SyncError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
