"""Test suite configuration.

Safety contract
---------------
This suite drops and recreates the entire schema, so it must only ever run
against a disposable database. Historically it read ``DATABASE_URL`` via
``setdefault``, which meant that exporting a development or production URL
pointed ``Base.metadata.drop_all()`` at real data.

The rules enforced here are:

1. The test database is declared by ``TEST_DATABASE_URL`` and nothing else.
   ``DATABASE_URL`` is never read as a source for the test target.
2. The target database name must look disposable (contain a ``test`` token).
3. The target must not be the application's own ``DATABASE_URL``.

If any rule fails the session aborts before a connection is opened. The schema
itself is created by running the real Alembic migrations rather than
``Base.metadata.create_all``, so tests exercise the migrated schema.
"""

import os
import pathlib
import re
import sys
import time

BACKEND_ROOT = pathlib.Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

DEFAULT_TEST_DATABASE_URL = (
    "postgresql+psycopg://postgres:postgres@localhost:5432/myapp_test"
)

# Matches a database name that is obviously disposable, e.g. "myapp_test",
# "test", "myapp_test_2", "myapp-test". Deliberately does not match
# "myapp_latest" or "contest".
_DISPOSABLE_NAME = re.compile(r"(?:^|[_\-])tests?(?:$|[_\-])", re.IGNORECASE)

_ENV_FILE = BACKEND_ROOT / ".env"

_HOW_TO_FIX = (
    "Point the suite at a disposable database, for example:\n"
    "    export TEST_DATABASE_URL="
    "postgresql+psycopg://postgres:postgres@localhost:5432/myapp_test\n"
    "or use the bundled Postgres:\n"
    "    docker compose -f backend/docker-compose.yml up -d postgres"
)


def _database_name(url: str) -> str:
    """Best-effort extraction of the database name from a SQLAlchemy URL."""
    without_query = url.split("?", 1)[0].rstrip("/")
    return without_query.rsplit("/", 1)[-1]


def _application_database_url() -> str | None:
    """The database the app itself would use, from the env or from .env.

    Only used to prove the test target is a *different* database.
    """
    from_env = os.environ.get("DATABASE_URL")
    if from_env:
        return from_env
    if _ENV_FILE.exists():
        for line in _ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line.startswith("DATABASE_URL="):
                return line.split("=", 1)[1].strip().strip("'\"")
    return None


def resolve_test_database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL", "").strip()
    if not url:
        raise RuntimeError(
            "TEST_DATABASE_URL is not set. This suite drops and recreates the "
            "database schema, so it refuses to guess a target.\n" + _HOW_TO_FIX
        )

    name = _database_name(url)

    # Checked before the naming rule so the most dangerous case is always
    # reported as such, even when the name also looks non-disposable.
    app_url = _application_database_url()
    if app_url and _database_name(app_url) == name:
        raise RuntimeError(
            f"Refusing to run: TEST_DATABASE_URL points at {name!r}, which is "
            "the application's own DATABASE_URL. This suite drops and recreates "
            "the schema, so it would destroy that database. Set "
            "TEST_DATABASE_URL to a separate disposable database.\n" + _HOW_TO_FIX
        )

    if not name or not _DISPOSABLE_NAME.search(name):
        raise RuntimeError(
            f"Refusing to run: TEST_DATABASE_URL points at database {name!r}, "
            "which does not look like a disposable test database. Its name "
            "must contain a 'test' token (e.g. 'myapp_test').\n" + _HOW_TO_FIX
        )

    return url


def _ensure_database_exists(url: str) -> None:
    """Create the test database if it is missing.

    Only ever runs against a name that already passed the disposable check, and
    connects to the maintenance database rather than the target.
    """
    import psycopg
    from psycopg import sql
    from sqlalchemy.engine import make_url

    parsed = make_url(url)
    name = _database_name(url)

    # psycopg does not understand SQLAlchemy's "+psycopg" driver marker, and
    # str(url) masks the password, so render it explicitly.
    maintenance_url = (
        parsed.set(database="postgres")
        .render_as_string(hide_password=False)
        .replace("+psycopg", "")
    )

    try:
        conn = psycopg.connect(maintenance_url, connect_timeout=5)
    except Exception as exc:  # pragma: no cover - connection diagnostics
        raise RuntimeError(
            f"Could not reach PostgreSQL at {parsed.host}:{parsed.port}. "
            f"Is the server running?\n{_HOW_TO_FIX}"
        ) from exc

    with conn, conn.cursor() as cur:
        exists = cur.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (name,)
        ).fetchone()
        if exists is None:
            cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(name)))
            print(f"created test database {name!r}")


def _build_schema(url: str) -> None:
    """Create the schema using the real migrations.

    Any pre-existing schema is dropped first so a run always starts from a
    known-clean database and the full migration chain is exercised. The
    previous implementation used ``Base.metadata.create_all``, which meant the
    tests validated the ORM metadata rather than the migrations, and a
    previously drifted test database broke the run.

    This drops schema and data, which is safe here only because
    ``resolve_test_database_url`` has already proved the target is disposable.
    """
    from alembic import command
    from alembic.config import Config

    config = Config(str(BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND_ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", url)

    Base.metadata.drop_all(bind=engine)
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))
        conn.execute(text("CREATE SCHEMA public"))

    command.upgrade(config, "head")


# Resolve and export the target before anything imports app.db.database, which
# builds its engine at import time from settings.database_url.
TEST_DATABASE_URL = resolve_test_database_url()
os.environ["DATABASE_URL"] = TEST_DATABASE_URL
os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("GOOGLE_CLIENT_ID", "")
os.environ.setdefault("ENABLE_DEV_AUTH", "true")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402
from sqlalchemy.exc import OperationalError  # noqa: E402

from app.db.base import Base  # noqa: E402
from app.db.database import SessionLocal  # noqa: E402
from app.db.database import engine  # noqa: E402
from app.db.session import get_db  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True, scope="session")
def setup_database():
    _ensure_database_exists(TEST_DATABASE_URL)
    _build_schema(TEST_DATABASE_URL)


@pytest.fixture(autouse=True)
def clean_database():
    """Reset rows between tests.

    The table list is derived from the ORM metadata so tables added by a new
    migration are covered automatically. The previous hand-maintained DELETE
    list silently skipped any table it did not mention, which leaks state
    between tests once a table is added.

    ``TRUNCATE`` needs an ``ACCESS EXCLUSIVE`` lock on every listed table, so
    it can deadlock against a pooled connection that still holds a lock from
    an uncommitted transaction left over by an earlier test. Disposing the
    pool first rolls those connections back (and is cheap), and the truncate
    itself retries in case a live connection still holds a conflicting lock.
    """
    yield
    tables = ", ".join(f'"{t.name}"' for t in Base.metadata.sorted_tables)
    statement = text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE")
    for _ in range(3):
        try:
            with engine.begin() as conn:
                conn.execute(statement)
            return
        except OperationalError as exc:
            if "deadlock detected" not in str(exc.orig):
                raise
        finally:
            engine.dispose()
    raise RuntimeError("clean_database kept deadlocking on TRUNCATE")


@pytest.fixture()
def client():
    def override_get_db():
        db = SessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
