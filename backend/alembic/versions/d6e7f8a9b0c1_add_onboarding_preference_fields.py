"""Add onboarding preference fields

Revision ID: d6e7f8a9b0c1
Revises: c4d5e6f70819
Create Date: 2026-08-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd6e7f8a9b0c1'
down_revision: Union[str, Sequence[str], None] = 'c4d5e6f70819'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'user_preferences',
        sa.Column('max_daily_hours', sa.Integer(), nullable=False, server_default='8'),
    )
    op.add_column(
        'user_preferences',
        sa.Column(
            'default_duration_minutes',
            sa.Integer(),
            nullable=False,
            server_default='30',
        ),
    )
    op.add_column(
        'user_preferences',
        sa.Column(
            'default_priority',
            sa.String(length=20),
            nullable=False,
            server_default='medium',
        ),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('user_preferences', 'default_priority')
    op.drop_column('user_preferences', 'default_duration_minutes')
    op.drop_column('user_preferences', 'max_daily_hours')
