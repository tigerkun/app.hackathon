import time
from datetime import datetime
from fastapi import APIRouter, HTTPException, Depends, Header
from typing import Optional

from ...models.schemas import (
    UserCreate, UserLogin, PinLogin, BiometricRegister, BiometricLogin,
    UserResponse, TokenResponse
)
from ...core.security import (
    hash_password, verify_password, create_access_token, decode_access_token
)
from ...db.repository import db

router = APIRouter(prefix="/auth", tags=["Authentication & Session"])

def _to_user_response(user: dict) -> UserResponse:
    return UserResponse(
        id=user["id"],
        email=user["email"],
        name=user["name"],
        phone=user["phone"],
        emergency_contacts=user.get("emergency_contacts", []),
        is_active=user.get("is_active", True),
        biometrics_enabled=user.get("biometrics_enabled", False),
        has_pin=bool(user.get("pin")),
        created_at=user["created_at"]
    )

def get_current_user(authorization: Optional[str] = Header(None)) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = authorization.split(" ")[1]
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        raise HTTPException(status_code=401, detail="Invalid or expired session token")
    user_id = payload["sub"]
    user = db.users.get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User account not found")
    return user

@router.post("/signup", response_model=TokenResponse)
def signup(data: UserCreate):
    for u in db.users.values():
        if u["email"].lower() == data.email.lower():
            raise HTTPException(status_code=400, detail="Account with this email already exists")
        if u["phone"] == data.phone:
            raise HTTPException(status_code=400, detail="Account with this phone already exists")

    user_id = f"user_{int(time.time()*1000)}"
    user_dict = {
        "id": user_id,
        "email": data.email.lower(),
        "name": data.name,
        "phone": data.phone,
        "password_hash": hash_password(data.password),
        "pin": data.pin,
        "biometric_token": None,
        "biometrics_enabled": False,
        "emergency_contacts": [c.model_dump() if hasattr(c, "model_dump") else c.dict() for c in data.emergency_contacts],
        "is_active": True,
        "created_at": datetime.now().isoformat()
    }
    db.users[user_id] = user_dict
    token = create_access_token({"sub": user_id, "email": data.email})
    return TokenResponse(access_token=token, user=_to_user_response(user_dict))

@router.post("/login", response_model=TokenResponse)
def login(data: UserLogin):
    user = None
    for u in db.users.values():
        if u["email"].lower() == data.email_or_phone.lower() or u["phone"] == data.email_or_phone:
            user = u
            break
    if not user or not verify_password(data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid credentials provided")

    token = create_access_token({"sub": user["id"], "email": user["email"]})
    return TokenResponse(access_token=token, user=_to_user_response(user))

@router.post("/login-pin", response_model=TokenResponse)
def login_with_pin(data: PinLogin):
    user = None
    for u in db.users.values():
        if u["email"].lower() == data.email.lower():
            user = u
            break
    if not user or not user.get("pin") or user["pin"] != data.pin:
        raise HTTPException(status_code=401, detail="Invalid PIN or account not found")

    token = create_access_token({"sub": user["id"], "email": user["email"]})
    return TokenResponse(access_token=token, user=_to_user_response(user))

@router.post("/biometrics/register")
def register_biometrics(data: BiometricRegister, current_user: dict = Depends(get_current_user)):
    current_user["biometric_token"] = data.biometric_token
    current_user["biometrics_enabled"] = True
    return {"message": "Biometric credential registered successfully", "enabled": True}

@router.post("/biometrics/login", response_model=TokenResponse)
def login_biometric(data: BiometricLogin):
    user = None
    for u in db.users.values():
        if u.get("biometrics_enabled") and u.get("biometric_token") == data.biometric_token:
            user = u
            break
    if not user:
        raise HTTPException(status_code=401, detail="Biometric token not recognized or disabled")

    token = create_access_token({"sub": user["id"], "email": user["email"]})
    return TokenResponse(access_token=token, user=_to_user_response(user))

@router.get("/me", response_model=UserResponse)
def get_profile(current_user: dict = Depends(get_current_user)):
    return _to_user_response(current_user)

@router.post("/logout")
def logout(current_user: dict = Depends(get_current_user)):
    return {"message": "Logged out successfully"}
