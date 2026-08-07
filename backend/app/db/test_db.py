def main() -> None:
    from sqlalchemy import select

    from app.db.database import SessionLocal
    from app.models.user import User

    db = SessionLocal()
    try:
        users = db.scalars(select(User)).all()
        print(users)
    finally:
        db.close()


if __name__ == "__main__":
    main()
