"""Serverless entrypoint.

Migrations are NOT applied here. Applying them at import time meant every cold
start attempted a schema change, concurrent instances raced each other, and a
failure was swallowed so the instance kept serving against an incompatible
schema.

Migrations are now a deployment step:

    DATABASE_URL=... python -m scripts.migrate

This module only verifies that the database is at the revision the code
expects, and refuses to serve if it is not.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))  # backend/api
BACKEND_ROOT = os.path.dirname(HERE)  # backend/
PROJECT_ROOT = os.path.dirname(BACKEND_ROOT)

for path in (BACKEND_ROOT, PROJECT_ROOT):
    if path not in sys.path:
        sys.path.insert(0, path)


def _verify_schema() -> None:
    """Fail the cold start if the schema is not at the expected revision."""
    from app.db.database import engine
    from app.db.schema_check import SchemaOutOfDateError
    from app.db.schema_check import schema_location
    from app.db.schema_check import verify_schema_at_head

    if not os.getenv("DATABASE_URL"):
        # No database configured (e.g. a build step importing this module).
        # Nothing to verify, and nothing to serve.
        return

    try:
        revision = verify_schema_at_head(engine, script_location=schema_location())
    except SchemaOutOfDateError as exc:
        # Deliberately fatal: serving against an unknown schema produces
        # confusing failures far from the cause.
        raise RuntimeError(
            f"Refusing to start: {exc}"
        ) from exc
    print(f"schema at {revision}", flush=True)


_verify_schema()

from app.main import app  # noqa: E402
