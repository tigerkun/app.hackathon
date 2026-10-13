/**
 * SafeSphere Shared Incident Reports Contracts
 */

export type ReportCategory = 'Theft' | 'Harassment' | 'Accident' | 'Suspicious' | 'Other';
export type ReportStatus = 'pending' | 'under_investigation' | 'verified' | 'resolved';

export interface IncidentReport {
  id: string;
  type: ReportCategory;
  description: string;
  location: string;
  latitude?: number;
  longitude?: number;
  status: ReportStatus;
  created_at: string;
  reported_by?: string;
  attachments?: string[];
}
