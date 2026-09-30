import uuid
from datetime import datetime

from sqlalchemy import DateTime
from sqlalchemy import ForeignKey
from sqlalchemy import Index
from sqlalchemy import String
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped
from sqlalchemy.orm import mapped_column
from sqlalchemy.orm import relationship

from app.db.base import Base


class AuthSession(Base):
    """A server-side refresh session.

    Access tokens are stateless and short lived, but refresh tokens were
    previously stateless too: logout revoked nothing, and a refresh issued a new
    pair without invalidating the old token, so a copied refresh token stayed
    usable until it expired.

    Every refresh token now carries a ``jti`` that maps to one of these rows.
    Refreshing rotates the row (the old one is revoked and linked to its
    replacement). Presenting an already-rotated token follows the rotation
    chain forward to the current live session and rotates that instead, so a
    benign duplicate (e.g. concurrent refreshes from one device) never signs
    the user out. Only an explicitly logged-out or expired session refuses to
    refresh.
    """

    __tablename__ = "auth_sessions"
    __table_args__ = (
        Index("ix_auth_sessions_user_active", "user_id", "revoked_at"),
    )

    jti: Mapped[str] = mapped_column(
        String(64),
        primary_key=True,
        default=lambda: str(uuid.uuid4()),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )

    last_used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    revoked_reason: Mapped[str | None] = mapped_column(
        String(32),
        nullable=True,
    )

    replaced_by_jti: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
    )

    user_agent: Mapped[str | None] = mapped_column(
        String(256),
        nullable=True,
    )

    user: Mapped["User"] = relationship()  # noqa: F821
