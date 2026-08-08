"""Add habits tables

Revision ID: f1a2b3c4d5e6
Revises: a7b8c9d0e1f2
Create Date: 2026-08-07 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'f1a2b3c4d5e6'
down_revision: Union[str, Sequence[str], None] = 'a7b8c9d0e1f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'habits',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('repeat_weekdays', postgresql.ARRAY(sa.Integer()), nullable=True),
        sa.Column('daily_goal', sa.Integer(), server_default='1', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_habits_user_id'), 'habits', ['user_id'], unique=False)

    op.create_table(
        'habit_logs',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('habit_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('count', sa.Integer(), server_default='1', nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['habit_id'], ['habits.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_habit_logs_habit_id'), 'habit_logs', ['habit_id'], unique=False)
    op.create_index(op.f('ix_habit_logs_user_id'), 'habit_logs', ['user_id'], unique=False)
    op.create_index(op.f('ix_habit_logs_completed_at'), 'habit_logs', ['completed_at'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_habit_logs_completed_at'), table_name='habit_logs')
    op.drop_index(op.f('ix_habit_logs_user_id'), table_name='habit_logs')
    op.drop_index(op.f('ix_habit_logs_habit_id'), table_name='habit_logs')
    op.drop_table('habit_logs')
    op.drop_index(op.f('ix_habits_user_id'), table_name='habits')
    op.drop_table('habits')
