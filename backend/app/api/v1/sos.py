import time
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends
from typing import List, Optional

from ...models.schemas import SosTrigger, SosResolve, SosResponse
from .auth import get_current_user
from ...db.repository import db

router = APIRouter(prefix="/sos", tags=["SOS Emergency Dispatch"])

@router.post("/trigger", response_model=SosResponse, status_code=201)
def trigger_sos(data: SosTrigger, current_user: dict = Depends(get_current_user)):
    sos_id = f"sos_{int(time.time()*1000)}"
    emergency_contacts = current_user.get("emergency_contacts", [])

    sos_dict = {
        "id": sos_id,
        "user_id": current_user["id"],
        "user_name": current_user["name"],
        "user_phone": current_user["phone"],
        "latitude": data.latitude,
        "longitude": data.longitude,
        "alert_type": data.alert_type,
        "status": "active",
        "triggered_at": datetime.now().isoformat(),
        "resolved_at": None,
        "emergency_contacts_notified": len(emergency_contacts)
    }
    db.sos_alerts[sos_id] = sos_dict
    return SosResponse(**sos_dict)

@router.get("/active", response_model=List[SosResponse])
def get_active_sos_alerts():
    active = [s for s in db.sos_alerts.values() if s["status"] == "active"]
    active.sort(key=lambda s: s.get("triggered_at", ""), reverse=True)
    return [SosResponse(**s) for s in active]

@router.post("/{sos_id}/resolve", response_model=SosResponse)
def resolve_sos(sos_id: str, data: SosResolve, current_user: dict = Depends(get_current_user)):
    sos = db.sos_alerts.get(sos_id)
    if not sos:
        raise HTTPException(status_code=404, detail="SOS alert not found")

    # Verify that the user owns this SOS alert
    if sos["user_id"] != current_user["id"]:
        raise HTTPException(status_code=403, detail="Unauthorized to resolve an SOS triggered by another user")

    # If user has a PIN configured, require and verify it before resolving for false-coercion safety
    if current_user.get("pin"):
        if not data.pin or current_user["pin"] != data.pin:
            raise HTTPException(status_code=403, detail="Valid security PIN required for SOS cancellation")

    sos["status"] = "resolved"
    sos["resolved_at"] = datetime.now().isoformat()
    return SosResponse(**sos)

@router.get("/{sos_id}", response_model=SosResponse)
def get_sos(sos_id: str):
    sos = db.sos_alerts.get(sos_id)
    if not sos:
        raise HTTPException(status_code=404, detail="SOS alert not found")
    return SosResponse(**sos)
