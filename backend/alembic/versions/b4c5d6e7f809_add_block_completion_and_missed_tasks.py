"""Add block completion, task progress, and missed-task tracking

Revision ID: b4c5d6e7f809
Revises: c3f1a2b4d5e6
Create Date: 2026-08-09 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b4c5d6e7f809'
down_revision: Union[str, Sequence[str], None] = 'c3f1a2b4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'calendar_blocks',
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'calendar_blocks',
        sa.Column('completion_note', sa.Text(), nullable=True),
    )
    op.add_column(
        'tasks',
        sa.Column('progress_percent', sa.Integer(), server_default='0', nullable=False),
    )

    op.create_table(
        'task_misses',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('task_id', sa.UUID(), nullable=False),
        sa.Column('task_title', sa.String(length=255), nullable=False),
        sa.Column('category', sa.String(length=100), nullable=True),
        sa.Column('missed_deadline', sa.DateTime(timezone=True), nullable=True),
        sa.Column('reason', sa.Text(), nullable=True),
        sa.Column('minutes_remaining', sa.Integer(), nullable=True),
        sa.Column('rescheduled_to', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['task_id'], ['tasks.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_task_misses_task_id'), 'task_misses', ['task_id'], unique=False)
    op.create_index(op.f('ix_task_misses_user_id'), 'task_misses', ['user_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_task_misses_user_id'), table_name='task_misses')
    op.drop_index(op.f('ix_task_misses_task_id'), table_name='task_misses')
    op.drop_table('task_misses')
    op.drop_column('tasks', 'progress_percent')
    op.drop_column('calendar_blocks', 'completion_note')
    op.drop_column('calendar_blocks', 'completed_at')
