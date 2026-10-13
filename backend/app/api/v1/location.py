import time
import secrets
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, Depends
from typing import Optional

from ...models.schemas import (
    LocationPing, ShareSessionCreate, ShareSessionResponse
)
from .auth import get_current_user
from ...db.repository import db

router = APIRouter(prefix="/location", tags=["Real-time Geolocation & Sharing"])

@router.post("/ping")
def update_location_ping(data: LocationPing, current_user: dict = Depends(get_current_user)):
    user_id = current_user["id"]
    current_user["last_location"] = {
        "latitude": data.latitude,
        "longitude": data.longitude,
        "accuracy": data.accuracy,
        "speed": data.speed,
        "heading": data.heading,
        "updated_at": data.timestamp or datetime.now().isoformat()
    }

    # If user has an active SOS, update SOS location
    for s in db.sos_alerts.values():
        if s["user_id"] == user_id and s["status"] == "active":
            s["latitude"] = data.latitude
            s["longitude"] = data.longitude

    # Update active location sharing sessions
    for session in db.share_sessions.values():
        if session["user_id"] == user_id and session.get("is_active", True):
            session["current_latitude"] = data.latitude
            session["current_longitude"] = data.longitude

    return {"status": "ok", "recorded_at": datetime.now().isoformat()}

@router.post("/share-session", response_model=ShareSessionResponse, status_code=201)
def create_share_session(data: ShareSessionCreate, current_user: dict = Depends(get_current_user)):
    session_id = f"share_{secrets.token_urlsafe(8)}"
    expires_at = (datetime.now() + timedelta(minutes=data.duration_minutes)).isoformat()

    session_dict = {
        "session_id": session_id,
        "user_id": current_user["id"],
        "user_name": current_user["name"],
        "tracking_url": f"https://safesphere.org/track/{session_id}",
        "expires_at": expires_at,
        "is_active": True,
        "current_latitude": data.initial_latitude,
        "current_longitude": data.initial_longitude,
        "recipient_phones": data.recipient_phones,
        "created_at": datetime.now().isoformat()
    }
    db.share_sessions[session_id] = session_dict
    return ShareSessionResponse(**session_dict)

@router.get("/track/{session_id}", response_model=ShareSessionResponse)
def get_share_session_status(session_id: str):
    session = db.share_sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Live share tracking session not found")

    # Check if expired
    if datetime.fromisoformat(session["expires_at"]) < datetime.now():
        session["is_active"] = False

    return ShareSessionResponse(**session)
