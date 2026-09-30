"""Apply database migrations as an explicit deployment step.

Usage (from ``backend/``):

    DATABASE_URL=postgresql+psycopg://... python -m scripts.migrate
    DATABASE_URL=postgresql+psycopg://... python -m scripts.migrate --check

``--check`` reports whether the database is at head without changing anything,
which is what the serverless entrypoint uses.

This is intentionally a separate command. It used to run as an import side
effect in ``api/index.py``, so every serverless cold start tried to migrate,
concurrent instances raced, and failures were swallowed.
"""

import argparse
import sys

from alembic import command
from alembic.config import Config

from app.core.config import settings
from app.db.database import engine
from app.db.schema_check import SchemaOutOfDateError
from app.db.schema_check import schema_location
from app.db.schema_check import verify_schema_at_head


def _config() -> Config:
    config = Config("alembic.ini")
    config.set_main_option("script_location", schema_location())
    config.set_main_option("sqlalchemy.url", settings.database_url)
    return config


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify the schema is at head without applying anything.",
    )
    args = parser.parse_args(argv)

    if args.check:
        try:
            revision = verify_schema_at_head(engine, script_location=schema_location())
        except SchemaOutOfDateError as exc:
            print(f"schema check FAILED: {exc}", file=sys.stderr)
            return 1
        print(f"schema check OK: at {revision}")
        return 0

    target = "head"
    print(f"applying migrations to {settings.database_url.rsplit('@')[-1]}")
    command.upgrade(_config(), target)
    print(f"migrations applied: now at {verify_schema_at_head(engine, script_location=schema_location())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
