"""add replication support: revisions, tombstones, change log, op dedup

Revision ID: f2e3d4c5b6a7
Revises: e1a2b3c4d5e6
Create Date: 2026-09-30 15:10:00.000000

Backs the replication protocol:

* ``revision``   - bumped on every server-side change, so a client can detect
                   that it edited a record another device had already changed.
* ``deleted_at`` - deletes become tombstones so other devices can learn that a
                   record disappeared. Previously a delete was a hard delete and
                   an incremental download could not tell another device.
* ``sync_changes``  - a server-assigned monotonic sequence, so the download
                   cursor is issued by the server instead of being the device's
                   own clock reading after a download. Clock-based cursors miss
                   changes committed while the download was in flight.
* ``sync_operations`` - records applied operation ids so a retried push replays
                   the original result instead of applying twice.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "f2e3d4c5b6a7"
down_revision: Union[str, Sequence[str], None] = "e1a2b3c4d5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

ENTITY_TABLES = ("tasks", "calendar_blocks")


def upgrade() -> None:
    for table in ENTITY_TABLES:
        op.add_column(
            table,
            sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.add_column(
            table,
            sa.Column(
                "revision",
                sa.Integer(),
                nullable=False,
                server_default="1",
            ),
        )

    op.create_table(
        "sync_changes",
        sa.Column("seq", sa.BigInteger(), autoincrement=True, primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("entity", sa.String(length=32), nullable=False),
        sa.Column("entity_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        # 'upsert' or 'delete'
        sa.Column("operation", sa.String(length=16), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    # The pull query is always (user_id, seq > cursor) ordered by seq.
    op.create_index(
        "ix_sync_changes_user_seq",
        "sync_changes",
        ["user_id", "seq"],
    )

    op.create_table(
        "sync_operations",
        sa.Column("operation_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("entity", sa.String(length=32), nullable=False),
        sa.Column("entity_id", postgresql.UUID(as_uuid=True), nullable=False),
        # The serialized outcome, replayed verbatim if the same operation id is
        # pushed again after a lost response.
        sa.Column("result", postgresql.JSONB(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_sync_operations_user",
        "sync_operations",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_sync_operations_user", table_name="sync_operations")
    op.drop_table("sync_operations")
    op.drop_index("ix_sync_changes_user_seq", table_name="sync_changes")
    op.drop_table("sync_changes")
    for table in ENTITY_TABLES:
        op.drop_column(table, "revision")
        op.drop_column(table, "deleted_at")
