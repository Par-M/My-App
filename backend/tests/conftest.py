import os

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+psycopg://Parthiv:testing123@localhost:5432/myapp_test",
)
os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("GOOGLE_CLIENT_ID", "")
os.environ.setdefault("ENABLE_DEV_AUTH", "true")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.db.base import Base
from app.db.database import SessionLocal
from app.db.database import engine
from app.db.session import get_db
from app.main import app


@pytest.fixture(autouse=True, scope="session")
def setup_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


@pytest.fixture(autouse=True)
def clean_database():
    yield
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM tasks"))
        conn.execute(text("DELETE FROM users"))


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
