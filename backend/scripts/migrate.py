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
import os
import sys

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine

from app.db.schema_check import SchemaOutOfDateError
from app.db.schema_check import schema_location
from app.db.schema_check import verify_schema_at_head


def _database_url() -> str:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        print(
            "DATABASE_URL is not set. Refusing to guess a target database.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql+psycopg://", 1)
    return url


def _config() -> Config:
    config = Config("alembic.ini")
    config.set_main_option("script_location", schema_location())
    config.set_main_option("sqlalchemy.url", _database_url())
    return config


def _engine():
    return create_engine(_database_url(), pool_pre_ping=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify the schema is at head without applying anything.",
    )
    args = parser.parse_args(argv)

    engine = _engine()

    if args.check:
        try:
            revision = verify_schema_at_head(engine, script_location=schema_location())
        except SchemaOutOfDateError as exc:
            print(f"schema check FAILED: {exc}", file=sys.stderr)
            return 1
        print(f"schema check OK: at {revision}")
        return 0

    target = "head"
    print(f"applying migrations to {_database_url().rsplit('@')[-1]}")
    command.upgrade(_config(), target)
    print(f"migrations applied: now at {verify_schema_at_head(engine, script_location=schema_location())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
