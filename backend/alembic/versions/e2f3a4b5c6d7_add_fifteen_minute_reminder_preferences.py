"""Add fifteen minute reminder preference fields

Revision ID: e2f3a4b5c6d7
Revises: c8d9e0f1a2b3
Create Date: 2026-09-03 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e2f3a4b5c6d7'
down_revision: Union[str, Sequence[str], None] = 'c8d9e0f1a2b3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'notification_preferences',
        sa.Column(
            'fifteen_minute_reminder_enabled',
            sa.Boolean(),
            nullable=False,
            server_default=sa.text('true'),
        ),
    )
    op.add_column(
        'notification_preferences',
        sa.Column(
            'fifteen_minute_reminder_lead_minutes',
            sa.Integer(),
            nullable=False,
            server_default=sa.text('15'),
        ),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('notification_preferences', 'fifteen_minute_reminder_lead_minutes')
    op.drop_column('notification_preferences', 'fifteen_minute_reminder_enabled')
