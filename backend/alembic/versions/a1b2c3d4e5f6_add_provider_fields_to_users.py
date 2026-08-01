"""add provider fields to users

Revision ID: a1b2c3d4e5f6
Revises: d32020363e68
Create Date: 2026-08-01 07:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = 'd32020363e68'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('users', sa.Column('provider', sa.String(), nullable=True))
    op.add_column('users', sa.Column('provider_user_id', sa.String(), nullable=True))

    op.execute(
        "UPDATE users "
        "SET provider = 'dev', "
        "provider_user_id = COALESCE(email, 'legacy-' || id::text) "
        "WHERE provider IS NULL"
    )

    op.alter_column('users', 'provider', nullable=False)
    op.alter_column('users', 'provider_user_id', nullable=False)

    op.create_index(op.f('ix_users_provider_user_id'), 'users', ['provider_user_id'], unique=False)
    op.create_unique_constraint('uq_users_provider_user_id', 'users', ['provider', 'provider_user_id'])

    op.drop_index(op.f('ix_users_apple_id'), table_name='users')
    op.drop_column('users', 'apple_id')


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column('users', sa.Column('apple_id', sa.String(), nullable=False, server_default=''))
    op.create_index(op.f('ix_users_apple_id'), 'users', ['apple_id'], unique=True)

    op.drop_constraint('uq_users_provider_user_id', 'users', type_='unique')
    op.drop_index(op.f('ix_users_provider_user_id'), table_name='users')
    op.drop_column('users', 'provider_user_id')
    op.drop_column('users', 'provider')
