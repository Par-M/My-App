"""Add user-customizable order (position) to tasks and habits

Revision ID: a5b6c7d8e9f0
Revises: e2f3a4b5c6d7
Create Date: 2026-09-11 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a5b6c7d8e9f0'
down_revision: Union[str, Sequence[str], None] = 'e2f3a4b5c6d7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'tasks',
        sa.Column(
            'position',
            sa.Integer(),
            nullable=False,
            server_default=sa.text('0'),
        ),
    )
    op.add_column(
        'habits',
        sa.Column(
            'position',
            sa.Integer(),
            nullable=False,
            server_default=sa.text('0'),
        ),
    )

    # Backfill existing rows so the current default task order (newest first)
    # and habit order (oldest first) are preserved as the "My Order" positions.
    op.execute(
        """
        UPDATE tasks
        SET position = sub.rn
        FROM (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY user_id
                       ORDER BY created_at DESC, id
                   ) - 1 AS rn
            FROM tasks
        ) sub
        WHERE tasks.id = sub.id
        """
    )
    op.execute(
        """
        UPDATE habits
        SET position = sub.rn
        FROM (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY user_id
                       ORDER BY created_at ASC, id
                   ) - 1 AS rn
            FROM habits
        ) sub
        WHERE habits.id = sub.id
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('habits', 'position')
    op.drop_column('tasks', 'position')