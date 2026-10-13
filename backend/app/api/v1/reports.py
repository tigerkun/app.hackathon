import time
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends, Query
from typing import List, Optional

from ...models.schemas import (
    ReportCreate, ReportResponse, ReportStatusUpdate, ReportStatusEnum, IncidentTypeEnum
)
from .auth import get_current_user
from ...db.repository import db

router = APIRouter(prefix="/reports", tags=["Incident Reporting"])

@router.get("", response_model=List[ReportResponse])
def list_reports(
    status: Optional[ReportStatusEnum] = None,
    type: Optional[IncidentTypeEnum] = None,
    limit: int = Query(default=50, ge=1, le=100)
):
    results = list(db.reports.values())
    if status:
        results = [r for r in results if r["status"] == status.value]
    if type:
        results = [r for r in results if r["type"] == type.value]
    results.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    return [ReportResponse(**r) for r in results[:limit]]

@router.post("", response_model=ReportResponse, status_code=201)
def submit_report(data: ReportCreate, authorization: Optional[str] = None):
    # Support both authenticated user reports and anonymous community reports
    reported_by = None
    if authorization and authorization.startswith("Bearer "):
        try:
            user = get_current_user(authorization)
            reported_by = user["id"]
        except Exception:
            pass

    report_id = f"rep_{int(time.time()*1000)}"
    report_dict = {
        "id": report_id,
        "type": data.type.value,
        "description": data.description,
        "location": data.location,
        "latitude": data.latitude,
        "longitude": data.longitude,
        "status": ReportStatusEnum.pending.value,
        "created_at": datetime.now().isoformat(),
        "reported_by": reported_by
    }
    db.reports[report_id] = report_dict
    return ReportResponse(**report_dict)

@router.get("/{report_id}", response_model=ReportResponse)
def get_report(report_id: str):
    report = db.reports.get(report_id)
    if not report:
        raise HTTPException(status_code=404, detail="Incident report not found")
    return ReportResponse(**report)

@router.patch("/{report_id}/status", response_model=ReportResponse)
def update_report_status(report_id: str, data: ReportStatusUpdate, current_user: dict = Depends(get_current_user)):
    report = db.reports.get(report_id)
    if not report:
        raise HTTPException(status_code=404, detail="Incident report not found")

    report["status"] = data.status.value
    return ReportResponse(**report)
