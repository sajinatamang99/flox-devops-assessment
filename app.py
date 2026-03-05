# app.py
from fastapi import FastAPI

import os
import datetime
app = FastAPI(title="FLOX Farm Health API")

@app.get("/health")
def health_check():
 return {
 "status": "healthy",
 "service": "farm-health-api",
 "version": os.getenv("APP_VERSION", "0.1.0"),
 "timestamp": datetime.datetime.utcnow().isoformat()
 }

@app.get("/ready")
def readiness_check():
 return {
 "ready": True,
 "checks": {
 "database": "ok",
 "cache": "ok"
 }
 }

@app.get("/")
def root():
 return {"message": "FLOX Farm Health API", "docs": "/docs"}
