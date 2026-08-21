"""update work hours default to 5.5-21.5

Revision ID: d4e5f6a7b8c9
Revises: c3f1a2b4d5e6
Create Date: 2026-05-11

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "d4e5f6a7b8c9"
down_revision: Union[str, None] = "c3f1a2b4d5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Update column defaults
    op.alter_column("user_preferences", "work_hours_start", server_default="5.5")
    op.alter_column("user_preferences", "work_hours_end", server_default="21.5")
    # Migrate existing rows that still use old defaults 9-17 to new 5.5-21.5
    op.execute("UPDATE user_preferences SET work_hours_start = 5.5 WHERE work_hours_start = 9")
    op.execute("UPDATE user_preferences SET work_hours_end = 21.5 WHERE work_hours_end = 17")


def downgrade() -> None:
    op.alter_column("user_preferences", "work_hours_start", server_default="9")
    op.alter_column("user_preferences", "work_hours_end", server_default="17")
    op.execute("UPDATE user_preferences SET work_hours_start = 9 WHERE work_hours_start = 5.5")
    op.execute("UPDATE user_preferences SET work_hours_end = 17 WHERE work_hours_end = 21.5")
