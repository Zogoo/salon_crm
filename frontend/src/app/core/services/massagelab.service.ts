import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  Appointment,
  ApprovalRequest,
  Availability,
  ClientRecord,
  DayBoard,
  Dashboard,
  Location,
  Service,
  ShiftBoard,
  StaffMember,
} from '../models';

/** One place for every domain call, so a view-layer change touches components only. */
@Injectable({ providedIn: 'root' })
export class MassagelabService {
  private readonly http = inject(HttpClient);
  private readonly base = environment.apiUrl;

  locations(): Observable<{ locations: Location[] }> {
    return this.http.get<{ locations: Location[] }>(`${this.base}/locations`);
  }

  location(id: number): Observable<Location> {
    return this.http.get<Location>(`${this.base}/locations/${id}`);
  }

  services(locationId: number): Observable<{ services: Service[] }> {
    const params = new HttpParams().set('location_id', locationId);
    return this.http.get<{ services: Service[] }>(`${this.base}/services`, { params });
  }

  dashboard(locationId: number, date: string): Observable<Dashboard> {
    const params = new HttpParams().set('location_id', locationId).set('date', date);
    return this.http.get<Dashboard>(`${this.base}/dashboard`, { params });
  }

  dayBoard(locationId: number, date: string): Observable<DayBoard> {
    const params = new HttpParams().set('location_id', locationId).set('date', date);
    return this.http.get<DayBoard>(`${this.base}/appointments/calendar`, { params });
  }

  availability(
    locationId: number,
    variantIds: number[],
    date: string,
    requestedStaffId?: number | null,
  ): Observable<Availability> {
    let params = new HttpParams().set('location_id', locationId).set('date_from', date);
    variantIds.forEach((id) => (params = params.append('service_variant_ids[]', id)));
    if (requestedStaffId) {
      params = params.set('requested_staff_profile_id', requestedStaffId);
    }
    return this.http.get<Availability>(`${this.base}/availability`, { params });
  }

  book(payload: Record<string, unknown>): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments`, { appointment: payload });
  }

  appointment(id: number): Observable<Appointment> {
    return this.http.get<Appointment>(`${this.base}/appointments/${id}`);
  }

  transition(id: number, to: string, reason?: string): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/transition`, { to, reason });
  }

  clients(search = ''): Observable<{ clients: ClientRecord[] }> {
    const params = new HttpParams().set('search', search);
    return this.http.get<{ clients: ClientRecord[] }>(`${this.base}/clients`, { params });
  }

  client(id: number): Observable<ClientRecord> {
    return this.http.get<ClientRecord>(`${this.base}/clients/${id}`);
  }

  createClient(client: Partial<ClientRecord>): Observable<ClientRecord> {
    return this.http.post<ClientRecord>(`${this.base}/clients`, { client });
  }

  savePreferences(id: number, preference: Record<string, unknown>): Observable<ClientRecord> {
    return this.http.put<ClientRecord>(`${this.base}/clients/${id}/preferences`, { preference });
  }

  staff(locationId: number): Observable<{ staff: StaffMember[] }> {
    const params = new HttpParams().set('location_id', locationId);
    return this.http.get<{ staff: StaffMember[] }>(`${this.base}/staff`, { params });
  }

  staffMember(id: number): Observable<StaffMember> {
    return this.http.get<StaffMember>(`${this.base}/staff/${id}`);
  }

  shifts(locationId: number, date: string): Observable<ShiftBoard> {
    const params = new HttpParams().set('location_id', locationId).set('date', date);
    return this.http.get<ShiftBoard>(`${this.base}/shifts`, { params });
  }

  approvalRequests(): Observable<{ approval_requests: ApprovalRequest[] }> {
    return this.http.get<{ approval_requests: ApprovalRequest[] }>(`${this.base}/approval_requests`);
  }

  decideApproval(id: number, decision: 'approve' | 'reject'): Observable<ApprovalRequest> {
    return this.http.post<ApprovalRequest>(`${this.base}/approval_requests/${id}/${decision}`, {});
  }
}
