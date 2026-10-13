import time
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends, Query
from typing import List, Optional

from ...models.schemas import MarkerCreate, MarkerResponse
from .auth import get_current_user
from ...db.repository import db

router = APIRouter(prefix="/markers", tags=["Safety Markers & Safe Zones"])

@router.get("", response_model=List[MarkerResponse])
def list_markers(
    category: Optional[str] = None,
    limit: int = Query(default=50, ge=1, le=100)
):
    markers = list(db.markers.values())
    if category:
        markers = [m for m in markers if m["category"].lower() == category.lower()]
    return [MarkerResponse(**m) for m in markers[:limit]]

@router.get("/nearby", response_model=List[MarkerResponse])
def get_nearby_markers(
    latitude: float = Query(..., ge=-90.0, le=90.0),
    longitude: float = Query(..., ge=-180.0, le=180.0),
    radius_km: float = Query(default=10.0, ge=0.1, le=100.0)
):
    nearby = []
    for m in db.markers.values():
        dist = db.haversine_distance(latitude, longitude, m["latitude"], m["longitude"])
        if dist <= radius_km:
            marker_data = dict(m)
            marker_data["distance_km"] = round(dist, 2)
            nearby.append(marker_data)

    nearby.sort(key=lambda x: x.get("distance_km", 9999))
    return [MarkerResponse(**m) for m in nearby]

@router.post("", response_model=MarkerResponse, status_code=201)
def add_marker(data: MarkerCreate, current_user: dict = Depends(get_current_user)):
    marker_id = f"marker_{int(time.time()*1000)}"
    marker_dict = {
        "id": marker_id,
        "name": data.name,
        "category": data.category.value,
        "latitude": data.latitude,
        "longitude": data.longitude,
        "address": data.address,
        "is_verified": data.is_verified,
        "created_at": datetime.now().isoformat()
    }
    db.markers[marker_id] = marker_dict
    return MarkerResponse(**marker_dict)
