from fastapi import FastAPI

app = FastAPI(title="LajkonikGO API")


@app.get("/health")
def health_check():
    return {"status": "ok"}