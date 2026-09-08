import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  Appointment,
  ApprovalRequest,
  Availability,
  CareNote,
  ClientLogRow,
  ClientRecord,
  DailyRevenue,
  DayBoard,
  Dashboard,
  EarningPeriod,
  EarningsReport,
  GiftCard,
  GiftCardLiability,
  Location,
  MembershipRecord,
  NoShowReport,
  Order,
  PaymentMethod,
  RetentionReport,
  Service,
  ShiftBoard,
  StaffMember,
  UtilizationReport,
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

  // --- Checkout ---

  openOrder(appointmentId: number): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders`, {
      order: { appointment_id: appointmentId },
    });
  }

  order(id: number): Observable<Order> {
    return this.http.get<Order>(`${this.base}/orders/${id}`);
  }

  addPayment(id: number, method: PaymentMethod, amountCents: number, reference?: string) {
    return this.http.post<Order>(`${this.base}/orders/${id}/payments`, {
      method,
      amount_cents: amountCents,
      reference,
    });
  }

  redeemGiftCard(id: number, code: string, amountCents: number): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${id}/gift_card_redemptions`, {
      code,
      amount_cents: amountCents,
    });
  }

  applyMembershipCredit(id: number, override = false): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${id}/membership_credit`, {
      cross_location_override: override,
    });
  }

  setTip(id: number, amountCents: number): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${id}/tips`, { amount_cents: amountCents });
  }

  settleOrder(id: number): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${id}/settle`, {});
  }

  /** BR-23: payments are immutable; voiding is the sanctioned correction. */
  voidPayment(orderId: number, paymentId: number, reason: string): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${orderId}/payments/${paymentId}/void`, {
      reason,
    });
  }

  // --- Gift cards ---

  giftCards(search = '', status = ''): Observable<{ gift_cards: GiftCard[] }> {
    let params = new HttpParams();
    if (search) params = params.set('search', search);
    if (status) params = params.set('status', status);
    return this.http.get<{ gift_cards: GiftCard[] }>(`${this.base}/gift_cards`, { params });
  }

  giftCard(code: string): Observable<GiftCard> {
    return this.http.get<GiftCard>(`${this.base}/gift_cards/${code}`);
  }

  issueGiftCard(payload: Record<string, unknown>): Observable<GiftCard> {
    return this.http.post<GiftCard>(`${this.base}/gift_cards`, { gift_card: payload });
  }

  // --- Membership ---

  memberships(): Observable<{ memberships: MembershipRecord[] }> {
    return this.http.get<{ memberships: MembershipRecord[] }>(`${this.base}/memberships`);
  }

  membership(id: number): Observable<MembershipRecord> {
    return this.http.get<MembershipRecord>(`${this.base}/memberships/${id}`);
  }

  enrolMembership(payload: Record<string, unknown>): Observable<MembershipRecord> {
    return this.http.post<MembershipRecord>(`${this.base}/memberships`, { membership: payload });
  }

  recordMembershipPayment(id: number, method: PaymentMethod): Observable<MembershipRecord> {
    return this.http.post<MembershipRecord>(`${this.base}/memberships/${id}/record_payment`, {
      method,
    });
  }

  cancelMembership(id: number): Observable<MembershipRecord> {
    return this.http.post<MembershipRecord>(
      `${this.base}/memberships/${id}/request_cancellation`,
      {},
    );
  }

  // --- Earnings ---

  earningPeriods(): Observable<{ periods: EarningPeriod[] }> {
    return this.http.get<{ periods: EarningPeriod[] }>(`${this.base}/earning_periods`);
  }

  buildPeriod(id: number): Observable<EarningPeriod> {
    return this.http.post<EarningPeriod>(`${this.base}/earning_periods/${id}/build`, {});
  }

  lockPeriod(id: number): Observable<EarningPeriod> {
    return this.http.post<EarningPeriod>(`${this.base}/earning_periods/${id}/lock`, {});
  }

  periodStatements(id: number): Observable<EarningPeriod> {
    return this.http.get<EarningPeriod>(`${this.base}/earning_periods/${id}/statements`);
  }

  staffEarnings(staffProfileId: number, from: string, to: string): Observable<EarningsReport> {
    const params = new HttpParams()
      .set('staff_profile_id', staffProfileId)
      .set('from', from)
      .set('to', to);
    return this.http.get<EarningsReport>(`${this.base}/reports/staff_earnings`, { params });
  }

  addEarningLine(payload: Record<string, unknown>) {
    return this.http.post(`${this.base}/earning_lines`, payload);
  }

  // --- Reports ---

  dailyRevenue(locationId: number, from: string, to: string): Observable<DailyRevenue> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<DailyRevenue>(`${this.base}/reports/daily_revenue`, { params });
  }

  clientLog(locationId: number, date: string): Observable<{ date: string; rows: ClientLogRow[] }> {
    const params = new HttpParams().set('location_id', locationId).set('date', date);
    return this.http.get<{ date: string; rows: ClientLogRow[] }>(
      `${this.base}/reports/client_log`,
      { params },
    );
  }

  giftCardLiability(locationId: number): Observable<GiftCardLiability> {
    const params = new HttpParams().set('location_id', locationId);
    return this.http.get<GiftCardLiability>(`${this.base}/reports/gift_card_liability`, { params });
  }

  outstandingFees(locationId: number) {
    const params = new HttpParams().set('location_id', locationId);
    return this.http.get<{ total_cents: number; orders: Record<string, unknown>[] }>(
      `${this.base}/reports/outstanding_fees`,
      { params },
    );
  }

  noShows(locationId: number, from: string, to: string): Observable<NoShowReport> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<NoShowReport>(`${this.base}/reports/no_shows`, { params });
  }

  utilization(locationId: number, from: string, to: string): Observable<UtilizationReport> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<UtilizationReport>(`${this.base}/reports/utilization`, { params });
  }

  clientRetention(locationId: number, from: string, to: string): Observable<RetentionReport> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<RetentionReport>(`${this.base}/reports/client_retention`, { params });
  }

  // --- Care notes and ratings ---

  careNotes(appointmentId: number): Observable<{ care_notes: CareNote[] }> {
    const params = new HttpParams().set('appointment_id', appointmentId);
    return this.http.get<{ care_notes: CareNote[] }>(`${this.base}/care_notes`, { params });
  }

  addCareNote(appointmentId: number, body: string): Observable<CareNote> {
    return this.http.post<CareNote>(`${this.base}/care_notes`, {
      appointment_id: appointmentId,
      body,
    });
  }

  kioskQueue(locationId: number) {
    const params = new HttpParams().set('location_id', locationId);
    return this.http.get<{
      appointments: { id: number; reference: string; client_name: string; therapist: string; time: string }[];
    }>(`${this.base}/ratings/kiosk_queue`, { params });
  }

  submitRating(payload: Record<string, unknown>) {
    return this.http.post(`${this.base}/ratings`, payload);
  }
}
