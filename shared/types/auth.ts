/**
 * SafeSphere Shared Auth Contracts & Types
 */

export interface EmergencyContact {
  name: string;
  phone: string;
  relationship: string;
}

export interface UserProfile {
  id: string;
  email: string;
  name: string;
  phone: string;
  emergency_contacts: EmergencyContact[];
  is_active: boolean;
  biometrics_enabled: boolean;
  has_pin: boolean;
  created_at: string;
}

export interface TokenResponse {
  access_token: string;
  token_type: string;
  user: UserProfile;
}

export interface PinAuthRequest {
  email: string;
  pin: string;
}

export interface BiometricAuthRequest {
  biometric_token: string;
}
