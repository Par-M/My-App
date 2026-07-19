from fastapi import FastAPI
app = FastAPI()


@app.get("/")
def root():
    return {"message": "Hello World"}

@app.get("/health")
def root():
    return {"status": "Healthy"}
    
    
    
