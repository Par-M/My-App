import os
import traceback

from fastapi import APIRouter
from fastapi import Header
from fastapi import HTTPException
from fastapi import status
from sqlalchemy import text

from app.db.session import SessionLocal

router = APIRouter(prefix="/admin", tags=["admin"])


def _require_admin_token(x_admin_token: str | None) -> None:
    expected = os.getenv("ADMIN_TOKEN")
    if not expected or x_admin_token != expected:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin token",
        )


@router.post("/migrate")
def run_migrations(
    x_admin_token: str | None = Header(default=None),
) -> dict:
    _require_admin_token(x_admin_token)

    report: dict = {}

    backend_root = os.path.dirname(os.path.abspath(__file__))  # routes/
    backend_root = os.path.dirname(backend_root)  # app/
    backend_root = os.path.dirname(backend_root)  # backend/
    script_dir = os.path.join(backend_root, "alembic")
    report["alembic_dir_exists"] = os.path.isdir(script_dir)
    versions_dir = os.path.join(script_dir, "versions")
    if os.path.isdir(versions_dir):
        report["version_files"] = sorted(os.listdir(versions_dir))

    db = SessionLocal()
    try:
        row = db.execute(text("SELECT version_num FROM alembic_version")).scalar()
        report["db_version_before"] = row
        cols = [
            r[0]
            for r in db.execute(
                text(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_name='tasks'"
                )
            )
        ]
        report["tasks_has_is_broken_down"] = "is_broken_down" in cols
    finally:
        db.close()

    try:
        from alembic import command
        from alembic.config import Config

        config = Config()
        config.set_main_option("script_location", script_dir)
        command.upgrade(config, "head")
        report["upgrade"] = "OK"
    except Exception:
        report["upgrade"] = "FAILED"
        report["upgrade_error"] = traceback.format_exc()[-2000:]

    db = SessionLocal()
    try:
        report["db_version_after"] = db.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar()
    finally:
        db.close()

    return report
