from fastapi import FastAPI

app = FastAPI(
    title="My App API",
    version="1.0.0"
)

@app.get("/")
def root():
    return {
        "message": "AI Scheduler API"
    }

@app.get("/health")
def health():
    return {
        "status": "healthy"
    }
