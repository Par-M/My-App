"""Add calendar blocks, AI recommendations, and user preferences

Revision ID: f7a8b9c0d1e2
Revises: e5d52c512bfb
Create Date: 2026-08-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'f7a8b9c0d1e2'
down_revision: Union[str, Sequence[str], None] = 'e5d52c512bfb'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'calendar_blocks',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('task_id', sa.UUID(), nullable=False),
        sa.Column('calendar_event_id', sa.String(length=255), nullable=True),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('start_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('end_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['task_id'], ['tasks.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_calendar_blocks_calendar_event_id'), 'calendar_blocks', ['calendar_event_id'], unique=False)
    op.create_index(op.f('ix_calendar_blocks_start_at'), 'calendar_blocks', ['start_at'], unique=False)
    op.create_index(op.f('ix_calendar_blocks_task_id'), 'calendar_blocks', ['task_id'], unique=False)
    op.create_index(op.f('ix_calendar_blocks_user_id'), 'calendar_blocks', ['user_id'], unique=False)

    op.create_table(
        'ai_recommendations',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('status', sa.Enum('pending', 'accepted', 'rejected', 'failed', name='recommendationstatus'), nullable=False),
        sa.Column('accepted', sa.Boolean(), nullable=False),
        sa.Column('reasoning', sa.Text(), nullable=True),
        sa.Column('recommendation', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('failure_reason', sa.Text(), nullable=True),
        sa.Column('retry_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_ai_recommendations_user_id'), 'ai_recommendations', ['user_id'], unique=False)

    op.create_table(
        'user_preferences',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('work_hours_start', sa.Integer(), nullable=False),
        sa.Column('work_hours_end', sa.Integer(), nullable=False),
        sa.Column('buffer_minutes', sa.Integer(), nullable=False),
        sa.Column('energy_level', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_user_preferences_user_id'),
    )
    op.create_index(op.f('ix_user_preferences_user_id'), 'user_preferences', ['user_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_user_preferences_user_id'), table_name='user_preferences')
    op.drop_table('user_preferences')
    op.drop_index(op.f('ix_ai_recommendations_user_id'), table_name='ai_recommendations')
    op.drop_table('ai_recommendations')
    op.drop_index(op.f('ix_calendar_blocks_user_id'), table_name='calendar_blocks')
    op.drop_index(op.f('ix_calendar_blocks_task_id'), table_name='calendar_blocks')
    op.drop_index(op.f('ix_calendar_blocks_start_at'), table_name='calendar_blocks')
    op.drop_index(op.f('ix_calendar_blocks_calendar_event_id'), table_name='calendar_blocks')
    op.drop_table('calendar_blocks')
