/**
 * SafeSphere Shared SOS & Emergency Alert Contracts
 */

export type AlertType = 'CRITICAL_SOS' | 'PANIC_BUTTON' | 'MEDICAL_EMERGENCY' | 'ACCIDENT';
export type SosStatus = 'active' | 'resolved' | 'cancelled';

export interface SosTriggerPayload {
  latitude: number;
  longitude: number;
  accuracy?: number;
  battery_level?: number;
  alert_type: AlertType;
  notes?: string;
}

export interface SosAlertResponse {
  id: string;
  user_id: string;
  user_name: string;
  user_phone: string;
  latitude: number;
  longitude: number;
  alert_type: AlertType;
  status: SosStatus;
  triggered_at: string;
  resolved_at?: string;
  emergency_contacts_notified: number;
}
