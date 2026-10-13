import hashlib
import hmac
import json
import base64
import time
from typing import Optional, Dict, Any
from .config import settings

def _b64_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')

def _b64_decode(data: str) -> bytes:
    padding = '=' * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)

def hash_password(password: str, salt: Optional[str] = None) -> str:
    """PBKDF2-HMAC-SHA256 password hashing with salt."""
    if salt is None:
        salt = base64.b64encode(hashlib.sha256(str(time.time()).encode()).digest()).decode()[:16]
    key = hashlib.pbkdf2_hmac(
        'sha256',
        password.encode('utf-8'),
        salt.encode('utf-8'),
        100000
    )
    return f"{salt}${_b64_encode(key)}"

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        salt, key = hashed_password.split('$')
        expected_key = hashlib.pbkdf2_hmac(
            'sha256',
            plain_password.encode('utf-8'),
            salt.encode('utf-8'),
            100000
        )
        return hmac.compare_digest(_b64_encode(expected_key), key)
    except Exception:
        return False

def create_access_token(data: Dict[str, Any], expires_delta_seconds: Optional[int] = None) -> str:
    """Create a standard JWT token using HS256."""
    header = {"alg": settings.ALGORITHM, "typ": "JWT"}
    payload = data.copy()
    expire = int(time.time()) + (expires_delta_seconds or (settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60))
    payload["exp"] = expire
    payload["iat"] = int(time.time())

    encoded_header = _b64_encode(json.dumps(header, separators=(',', ':')).encode('utf-8'))
    encoded_payload = _b64_encode(json.dumps(payload, separators=(',', ':')).encode('utf-8'))
    signing_input = f"{encoded_header}.{encoded_payload}".encode('utf-8')

    signature = hmac.new(settings.SECRET_KEY.encode('utf-8'), signing_input, hashlib.sha256).digest()
    encoded_signature = _b64_encode(signature)

    return f"{encoded_header}.{encoded_payload}.{encoded_signature}"

def decode_access_token(token: str) -> Optional[Dict[str, Any]]:
    """Verify and decode a standard JWT token."""
    try:
        parts = token.split('.')
        if len(parts) != 3:
            return None
        encoded_header, encoded_payload, encoded_signature = parts
        signing_input = f"{encoded_header}.{encoded_payload}".encode('utf-8')
        expected_sig = hmac.new(settings.SECRET_KEY.encode('utf-8'), signing_input, hashlib.sha256).digest()
        if not hmac.compare_digest(_b64_encode(expected_sig), encoded_signature):
            return None
        payload = json.loads(_b64_decode(encoded_payload).decode('utf-8'))
        if payload.get("exp", 0) < int(time.time()):
            return None
        return payload
    except Exception:
        return None
