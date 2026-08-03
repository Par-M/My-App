from fastapi import FastAPI

from app.api.auth import router as auth_router
from app.api.routes.tasks import router as tasks_router

app = FastAPI(
    title="AI Scheduler API",
)

app.include_router(auth_router, prefix="/api/v1")
app.include_router(tasks_router, prefix="/api/v1")


@app.get("/")
def root():
    return {"message": "AI Scheduler API"}
