"""Add fractional work hours and task productivity

Revision ID: e9f1a2b3c4d5
Revises: d6e7f8a9b0c1
Create Date: 2026-08-07 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'e9f1a2b3c4d5'
down_revision: Union[str, Sequence[str], None] = 'd6e7f8a9b0c1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

productivity_type = postgresql.ENUM(
    'fast', 'moderate', 'slow', name='taskproductivity'
)


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column(
        'user_preferences',
        'work_hours_start',
        existing_type=sa.Integer(),
        type_=sa.Float(),
        postgresql_using='work_hours_start::double precision',
    )
    op.alter_column(
        'user_preferences',
        'work_hours_end',
        existing_type=sa.Integer(),
        type_=sa.Float(),
        postgresql_using='work_hours_end::double precision',
    )
    productivity_type.create(op.get_bind(), checkfirst=True)
    op.add_column(
        'tasks',
        sa.Column('productivity', productivity_type, nullable=True),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('tasks', 'productivity')
    productivity_type.drop(op.get_bind(), checkfirst=True)
    op.alter_column(
        'user_preferences',
        'work_hours_start',
        existing_type=sa.Float(),
        type_=sa.Integer(),
        postgresql_using='round(work_hours_start)::int',
    )
    op.alter_column(
        'user_preferences',
        'work_hours_end',
        existing_type=sa.Float(),
        type_=sa.Integer(),
        postgresql_using='round(work_hours_end)::int',
    )
