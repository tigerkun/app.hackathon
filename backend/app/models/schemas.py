from pydantic import BaseModel, EmailStr, Field
from typing import List, Optional
from enum import Enum
from datetime import datetime

# ==================== Auth Schemas ====================

class EmergencyContact(BaseModel):
    name: str
    phone: str
    relationship: str = "Family"

class UserBase(BaseModel):
    email: str
    name: str
    phone: str
    emergency_contacts: List[EmergencyContact] = Field(default_factory=list)

class UserCreate(UserBase):
    password: str
    pin: Optional[str] = None  # 4-6 digit quick PIN

class UserLogin(BaseModel):
    email_or_phone: str
    password: str

class PinLogin(BaseModel):
    email: str
    pin: str

class BiometricRegister(BaseModel):
    biometric_token: str
    device_name: str = "Primary Mobile"

class BiometricLogin(BaseModel):
    biometric_token: str

class UserResponse(UserBase):
    id: str
    is_active: bool = True
    biometrics_enabled: bool = False
    has_pin: bool = False
    created_at: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse

# ==================== Incident Report Schemas ====================

class ReportStatusEnum(str, Enum):
    pending = "pending"
    under_investigation = "under_investigation"
    verified = "verified"
    resolved = "resolved"

class IncidentTypeEnum(str, Enum):
    theft = "Theft"
    harassment = "Harassment"
    accident = "Accident"
    suspicious = "Suspicious"
    other = "Other"

class ReportCreate(BaseModel):
    type: IncidentTypeEnum
    description: str
    location: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    attachments: List[str] = Field(default_factory=list)

class ReportResponse(BaseModel):
    id: str
    type: str
    description: str
    location: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    status: ReportStatusEnum
    created_at: str
    reported_by: Optional[str] = None

class ReportStatusUpdate(BaseModel):
    status: ReportStatusEnum
    notes: Optional[str] = None

# ==================== SOS Schemas ====================

class SosTrigger(BaseModel):
    latitude: float
    longitude: float
    accuracy: Optional[float] = None
    battery_level: Optional[int] = None
    alert_type: str = "CRITICAL_SOS"
    notes: Optional[str] = None

class SosResolve(BaseModel):
    reason: str = "User confirmed safe"
    pin: Optional[str] = None

class SosResponse(BaseModel):
    id: str
    user_id: str
    user_name: str
    user_phone: str
    latitude: float
    longitude: float
    alert_type: str
    status: str  # active, resolved, cancelled
    triggered_at: str
    resolved_at: Optional[str] = None
    emergency_contacts_notified: int = 0

# ==================== Safety Marker Schemas ====================

class MarkerCategory(str, Enum):
    police = "Police Station"
    hospital = "Hospital"
    safe_zone = "Verified Safe Zone"
    transit = "Well-lit Transit Hub"
    danger = "Caution Area"

class MarkerCreate(BaseModel):
    name: str
    category: MarkerCategory
    latitude: float
    longitude: float
    address: Optional[str] = None
    is_verified: bool = True

class MarkerResponse(BaseModel):
    id: str
    name: str
    category: str
    latitude: float
    longitude: float
    address: Optional[str] = None
    is_verified: bool = True
    created_at: str

# ==================== Geolocation & Live Sharing Schemas ====================

class LocationPing(BaseModel):
    latitude: float
    longitude: float
    accuracy: Optional[float] = None
    speed: Optional[float] = None
    heading: Optional[float] = None
    timestamp: Optional[str] = None

class ShareSessionCreate(BaseModel):
    duration_minutes: int = 60
    recipient_phones: List[str] = Field(default_factory=list)
    initial_latitude: float
    initial_longitude: float

class ShareSessionResponse(BaseModel):
    session_id: str
    tracking_url: str
    expires_at: str
    is_active: bool
    current_latitude: float
    current_longitude: float
