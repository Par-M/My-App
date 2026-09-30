import enum
import uuid
from datetime import datetime

from sqlalchemy import BigInteger
from sqlalchemy import DateTime
from sqlalchemy import ForeignKey
from sqlalchemy import Index
from sqlalchemy import Integer
from sqlalchemy import String
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped
from sqlalchemy.orm import mapped_column
from sqlalchemy.orm import relationship

from app.db.base import Base

ENTITY_TASK = "task"
ENTITY_BLOCK = "block"

# The two entity types that participate in replication.
SYNCED_ENTITIES = (ENTITY_TASK, ENTITY_BLOCK)


class SyncOperationKind(str, enum.Enum):
    """What a push operation asks the server to do."""

    upsert = "upsert"
    delete = "delete"


class SyncChange(Base):
    """One entry in the server's change log.

    ``seq`` is assigned by the database, so it is a server-issued monotonic
    cursor. Clients used to record their own clock reading after a download,
    which silently skipped any change committed while that download was in
    flight.
    """

    __tablename__ = "sync_changes"
    __table_args__ = (
        Index("ix_sync_changes_user_seq", "user_id", "seq"),
    )

    seq: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    entity: Mapped[str] = mapped_column(String(32), nullable=False)

    entity_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)

    revision: Mapped[int] = mapped_column(Integer, nullable=False)

    # 'upsert' or 'delete'
    operation: Mapped[str] = mapped_column(String(16), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


class SyncOperation(Base):
    """A push operation that has already been applied.

    The client retries a push until it is acknowledged, because it cannot tell
    the difference between "the request never arrived" and "the response was
    lost". Keying on the client-generated operation id means a retry replays
    the stored outcome instead of applying the change a second time.
    """

    __tablename__ = "sync_operations"

    operation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    entity: Mapped[str] = mapped_column(String(32), nullable=False)

    entity_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)

    result: Mapped[dict] = mapped_column(JSONB, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
