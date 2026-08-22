import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))  # backend/api
BACKEND_ROOT = os.path.dirname(HERE)  # backend/
PROJECT_ROOT = os.path.dirname(BACKEND_ROOT)

for path in (BACKEND_ROOT, PROJECT_ROOT):
    if path not in sys.path:
        sys.path.insert(0, path)


def _run_migrations() -> None:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        print("alembic skipped: DATABASE_URL not set", file=sys.stderr)
        return
    try:
        from alembic import command
        from alembic.config import Config

        config = Config()
        config.set_main_option("script_location", os.path.join(BACKEND_ROOT, "alembic"))
        command.upgrade(config, "head")
        print("alembic upgrade head: OK", flush=True)
    except Exception:
        traceback.print_exc()
        print("alembic upgrade head: FAILED (see traceback above)", file=sys.stderr, flush=True)


_run_migrations()

from app.main import app  # noqa: E402
