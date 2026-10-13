/**
 * SafeSphere Shared Safety Markers & Geolocation Contracts
 */

export type MarkerCategory =
  | 'Police Station'
  | 'Hospital'
  | 'Verified Safe Zone'
  | 'Well-lit Transit Hub'
  | 'Caution Area';

export interface SafetyMarkerItem {
  id: string;
  name: string;
  category: MarkerCategory;
  latitude: number;
  longitude: number;
  address?: string;
  is_verified: boolean;
  distance_km?: number;
  created_at: string;
}

export interface GeolocationPingPayload {
  latitude: number;
  longitude: number;
  accuracy?: number;
  speed?: number;
  heading?: number;
  timestamp?: string;
}

export interface LiveShareSession {
  session_id: string;
  tracking_url: string;
  expires_at: string;
  is_active: boolean;
  current_latitude: number;
  current_longitude: number;
  recipient_phones: string[];
}
