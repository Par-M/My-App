"""Add time tracking columns to tasks

Revision ID: a1b2c3d4e5f6
Revises: f7a8b9c0d1e2
Create Date: 2026-08-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b2c3d4e5f607'
down_revision: Union[str, Sequence[str], None] = 'f7a8b9c0d1e2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'tasks',
        sa.Column('actual_duration', sa.Integer(), nullable=True),
    )
    op.add_column(
        'tasks',
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'tasks',
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('tasks', 'completed_at')
    op.drop_column('tasks', 'started_at')
    op.drop_column('tasks', 'actual_duration')
