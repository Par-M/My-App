import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

if os.getenv("DATABASE_URL"):
    try:
        from alembic import command
        from alembic.config import Config

        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        config = Config(os.path.join(root, "alembic.ini"))
        command.upgrade(config, "head")
    except Exception as exc:
        print(f"alembic upgrade failed: {exc}", file=sys.stderr)

from app.main import app
