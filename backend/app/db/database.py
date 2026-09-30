from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings


def _normalized_url(url: str) -> str:
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql+psycopg://", 1)
    return url


engine = create_engine(
    _normalized_url(settings.database_url),
    pool_pre_ping=True,
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)

# Every write to a replicated entity must land in the change log, and the
# writes come from repositories, the scheduling service and the sync service
# alike, so the capture is attached to the session rather than to call sites.
from app.db.sync_events import register as _register_sync_events  # noqa: E402
from app.db.tombstone_filter import register as _register_tombstone_filter  # noqa: E402

_register_sync_events(SessionLocal)
_register_tombstone_filter(SessionLocal)
