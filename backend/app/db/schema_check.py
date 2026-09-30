"""Schema version verification.

Migrations are a deployment step, not something the application does at import
time. Running ``alembic upgrade head`` on a serverless cold start meant that
concurrent instances raced to apply the same schema changes, and a failure was
swallowed so the instance kept serving against an incompatible schema.

Instead the entrypoint calls :func:`verify_schema_at_head`, which fails loudly
and immediately if the database is not at the revision the code expects.
"""

import os

from sqlalchemy import text
from sqlalchemy.engine import Engine


class SchemaOutOfDateError(RuntimeError):
    """The database schema does not match the revision this code expects."""


def _head_revision(script_location: str) -> str | None:
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    config = Config()
    config.set_main_option("script_location", script_location)
    return ScriptDirectory.from_config(config).get_current_head()


def _current_revision(db: Engine) -> str | None:
    from sqlalchemy import inspect

    if "alembic_version" not in inspect(db).get_table_names():
        return None
    with db.connect() as conn:
        return conn.execute(text("SELECT version_num FROM alembic_version")).scalar()


def verify_schema_at_head(db: Engine, *, script_location: str) -> str:
    """Return the database revision, or raise if it is not at head.

    Raises:
        SchemaOutOfDateError: if the database is missing, empty, or behind.
    """
    head = _head_revision(script_location)
    current = _current_revision(db)

    if current is None:
        raise SchemaOutOfDateError(
            "The database has no alembic_version row, so no migrations have "
            f"been applied. Expected head {head!r}. Run "
            "'python -m scripts.migrate' (or 'alembic upgrade head') as a "
            "deployment step before serving traffic."
        )

    if current != head:
        raise SchemaOutOfDateError(
            f"Database schema is at {current!r} but this code expects {head!r}. "
            "Run 'python -m scripts.migrate' (or 'alembic upgrade head') as a "
            "deployment step before serving traffic."
        )

    return current


def schema_location() -> str:
    backend_root = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    )
    return os.path.join(backend_root, "alembic")
