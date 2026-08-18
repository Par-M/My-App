"""Add fixed event start/end times to tasks

Revision ID: c3f1a2b4d5e6
Revises: f1a2b3c4d5e6
Create Date: 2026-08-08 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c3f1a2b4d5e6'
down_revision: Union[str, Sequence[str], None] = 'f1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'tasks',
        sa.Column('start_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'tasks',
        sa.Column('end_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        op.f('ix_tasks_start_at'), 'tasks', ['start_at'], unique=False
    )
    op.create_index(
        op.f('ix_tasks_end_at'), 'tasks', ['end_at'], unique=False
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_tasks_end_at'), table_name='tasks')
    op.drop_index(op.f('ix_tasks_start_at'), table_name='tasks')
    op.drop_column('tasks', 'end_at')
    op.drop_column('tasks', 'start_at')
