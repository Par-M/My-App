from sqlalchemy import select

from app.db.database import SessionLocal
from app.models.user import User

db = SessionLocal()

users = db.scalars(select(User)).all()

print(users)
