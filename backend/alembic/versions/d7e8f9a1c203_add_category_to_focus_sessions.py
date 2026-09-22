"""add category to focus_sessions

Revision ID: d7e8f9a1c203
Revises: f2b3c4d5e6a7
Create Date: 2026-09-21 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd7e8f9a1c203'
down_revision: Union[str, Sequence[str], None] = 'f2b3c4d5e6a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'focus_sessions',
        sa.Column(
            'category',
            sa.String(length=100),
            nullable=True,
        ),
    )
    op.create_index(
        'ix_focus_sessions_category',
        'focus_sessions',
        ['category'],
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('ix_focus_sessions_category', table_name='focus_sessions')
    op.drop_column('focus_sessions', 'category')