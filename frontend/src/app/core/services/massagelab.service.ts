import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  Appointment,
  ApprovalRequest,
  AuditLogRecord,
  Availability,
  BusinessHour,
  CareNote,
  CatalogueService,
  CatalogueVariant,
  ClientGiftCard,
  ClientHistorySummary,
  ClientLogRow,
  ClientOrderHistory,
  ClientRating,
  ClientRecord,
  ClientVisit,
  Closure,
  DailyRevenue,
  Dashboard,
  DayBoard,
  EarningLine,
  EarningPeriod,
  EarningsReport,
  GiftCard,
  GiftCardLiability,
  ListQuery,
  Location,
  ManagerPayoutReport,
  MembershipRecord,
  MembershipReport,
  MonthlyRate,
  NoShowReport,
  Order,
  PageMeta,
  PaymentMethod,
  PreferenceVersion,
  Qualification,
  RatingAlertsReport,
  RatingsReport,
  RetentionReport,
  Room,
  RoomBlock,
  RosterShift,
  Service,
  SessionRate,
  ShiftBoard,
  ShiftBreak,
  StaffMember,
  StaffRequestRecord,
  UtilizationReport,
  VariantPrice,
} from '../models';

/** One place for every domain call, so a view-layer change touches components only. */
@Injectable({ providedIn: 'root' })
export class MassagelabService {
  private readonly http = inject(HttpClient);
  private readonly base = environment.apiUrl;

  auditLogs(filters: {
    action?: string;
    auditable_type?: string;
    from?: string;
    to?: string;
    page?: number;
    limit?: number;
  }): Observable<{ audit_logs: AuditLogRecord[]; meta: PageMeta }> {
    let params = new HttpParams();
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== '') {
        params = params.set(key === 'action' ? 'audit_action' : key, value);
      }
    });
    return this.http.get<{ audit_logs: AuditLogRecord[]; meta: PageMeta }>(
      `${this.base}/audit_logs`,
      { params },
    );
  }

  locations(): Observable<{ locations: Location[] }> {
    return this.http.get<{ locations: Location[] }>(`${this.base}/locations`);
  }

  /** Every active location by name — what a therapist chooses from when asking to move. */
  locationDirectory(): Observable<{ locations: { id: number; name: string }[] }> {
    return this.http.get<{ locations: { id: number; name: string }[] }>(
      `${this.base}/locations/directory`,
    );
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
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/transition`, {
      to,
      reason,
    });
  }

  updateAppointment(id: number, appointment: Record<string, unknown>): Observable<Appointment> {
    return this.http.patch<Appointment>(`${this.base}/appointments/${id}`, { appointment });
  }

  rescheduleAppointment(
    id: number,
    startAt: string,
    roomId?: number,
    staffProfileIds?: number[],
  ): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/reschedule`, {
      start_at: startAt,
      room_id: roomId,
      staff_profile_ids: staffProfileIds,
    });
  }

  /** Feedback 3.3: check in, start and complete in one server transaction. */
  completeForCheckout(id: number): Observable<{ appointment: Appointment; order_id: number }> {
    return this.http.post<{ appointment: Appointment; order_id: number }>(
      `${this.base}/appointments/${id}/complete_for_checkout`,
      {},
    );
  }

  recordDeposit(
    id: number,
    amountCents: number,
    method: string,
    reference?: string,
  ): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/deposit`, {
      amount_cents: amountCents,
      method,
      reference: reference || undefined,
    });
  }

  refundDeposit(id: number, reason?: string): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/deposit/refund`, {
      reason,
    });
  }

  assignAppointmentStaff(id: number, staffProfileIds: number[]): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/assign_staff`, {
      staff_profile_ids: staffProfileIds,
    });
  }

  repeatAppointment(
    id: number,
    intervalWeeks: number,
    count: number,
  ): Observable<{ appointments: Appointment[] }> {
    return this.http.post<{ appointments: Appointment[] }>(
      `${this.base}/appointments/${id}/repeat`,
      {
        interval_weeks: intervalWeeks,
        count,
      },
    );
  }

  replaceAppointmentService(id: number, variantIds: number[]): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/replace_service`, {
      service_variant_ids: variantIds,
    });
  }

  addAppointmentItems(id: number, variantIds: number[]): Observable<Appointment> {
    return this.http.post<Appointment>(`${this.base}/appointments/${id}/items`, {
      service_variant_ids: variantIds,
    });
  }

  removeAppointmentItem(id: number, itemId: number): Observable<Appointment> {
    return this.http.delete<Appointment>(`${this.base}/appointments/${id}/items/${itemId}`);
  }

  /** Paged, filtered, sorted client directory. */
  clientList(query: ListQuery): Observable<{ clients: ClientRecord[]; meta: PageMeta }> {
    return this.http.get<{ clients: ClientRecord[]; meta: PageMeta }>(`${this.base}/clients`, {
      params: this.listParams(query),
    });
  }

  staffList(query: ListQuery): Observable<{ staff: StaffMember[]; meta: PageMeta }> {
    return this.http.get<{ staff: StaffMember[]; meta: PageMeta }>(`${this.base}/staff`, {
      params: this.listParams(query),
    });
  }

  giftCardList(query: ListQuery): Observable<{ gift_cards: GiftCard[]; meta: PageMeta }> {
    return this.http.get<{ gift_cards: GiftCard[]; meta: PageMeta }>(`${this.base}/gift_cards`, {
      params: this.listParams(query),
    });
  }

  membershipList(
    query: ListQuery,
  ): Observable<{ memberships: MembershipRecord[]; meta: PageMeta }> {
    return this.http.get<{ memberships: MembershipRecord[]; meta: PageMeta }>(
      `${this.base}/memberships`,
      { params: this.listParams(query) },
    );
  }

  clientVisits(
    id: number,
    query: ListQuery,
  ): Observable<{ appointments: ClientVisit[]; meta: PageMeta }> {
    return this.http.get<{ appointments: ClientVisit[]; meta: PageMeta }>(
      `${this.base}/clients/${id}/appointments`,
      { params: this.listParams(query) },
    );
  }

  clientOrderPage(
    id: number,
    query: ListQuery,
  ): Observable<{ orders: ClientOrderHistory[]; meta: PageMeta }> {
    return this.http.get<{ orders: ClientOrderHistory[]; meta: PageMeta }>(
      `${this.base}/clients/${id}/orders`,
      { params: this.listParams(query) },
    );
  }

  private listParams(query: ListQuery): HttpParams {
    let params = new HttpParams();
    for (const [key, value] of Object.entries(query)) {
      if (value === undefined || value === null || value === '' || value === false) continue;
      params = params.set(key, String(value));
    }
    return params;
  }

  clients(search = ''): Observable<{ clients: ClientRecord[] }> {
    const params = new HttpParams().set('search', search);
    return this.http.get<{ clients: ClientRecord[] }>(`${this.base}/clients`, { params });
  }

  clientRatings(id: number): Observable<{ ratings: ClientRating[] }> {
    return this.http.get<{ ratings: ClientRating[] }>(`${this.base}/clients/${id}/ratings`);
  }

  clientGiftCards(id: number): Observable<{ gift_cards: ClientGiftCard[] }> {
    return this.http.get<{ gift_cards: ClientGiftCard[] }>(`${this.base}/clients/${id}/gift_cards`);
  }

  client(id: number): Observable<ClientRecord> {
    return this.http.get<ClientRecord>(`${this.base}/clients/${id}`);
  }

  createClient(client: Partial<ClientRecord>): Observable<ClientRecord> {
    return this.http.post<ClientRecord>(`${this.base}/clients`, { client });
  }

  updateClient(id: number, client: Partial<ClientRecord>): Observable<ClientRecord> {
    return this.http.patch<ClientRecord>(`${this.base}/clients/${id}`, { client });
  }

  mergeClient(id: number, intoClientId: number): Observable<ClientRecord> {
    return this.http.post<ClientRecord>(`${this.base}/clients/${id}/merge`, {
      into_client_id: intoClientId,
    });
  }

  clientPreferenceVersions(id: number): Observable<{ versions: PreferenceVersion[] }> {
    return this.http.get<{ versions: PreferenceVersion[] }>(
      `${this.base}/clients/${id}/preferences/versions`,
    );
  }

  clientOrders(id: number): Observable<{ orders: ClientOrderHistory[] }> {
    return this.http.get<{ orders: ClientOrderHistory[] }>(`${this.base}/clients/${id}/orders`);
  }

  clientHistorySummary(id: number): Observable<ClientHistorySummary> {
    return this.http.get<ClientHistorySummary>(`${this.base}/clients/${id}/history_summary`);
  }

  savePreferences(id: number, preference: Record<string, unknown>): Observable<ClientRecord> {
    return this.http.put<ClientRecord>(`${this.base}/clients/${id}/preferences`, { preference });
  }

  // `status` defaults to the working roster; 'all' reaches offboarded people.
  staff(locationId?: number, status = 'active'): Observable<{ staff: StaffMember[] }> {
    let params = new HttpParams().set('status', status);
    if (locationId) params = params.set('location_id', locationId);
    return this.http.get<{ staff: StaffMember[] }>(`${this.base}/staff`, { params });
  }

  staffMember(id: number): Observable<StaffMember> {
    return this.http.get<StaffMember>(`${this.base}/staff/${id}`);
  }

  shifts(locationId: number, date: string): Observable<ShiftBoard> {
    const params = new HttpParams().set('location_id', locationId).set('date', date);
    return this.http.get<ShiftBoard>(`${this.base}/shifts/day`, { params });
  }

  approvalRequests(): Observable<{ approval_requests: ApprovalRequest[] }> {
    return this.http.get<{ approval_requests: ApprovalRequest[] }>(
      `${this.base}/approval_requests`,
    );
  }

  decideApproval(id: number, decision: 'approve' | 'reject'): Observable<ApprovalRequest> {
    return this.http.post<ApprovalRequest>(`${this.base}/approval_requests/${id}/${decision}`, {});
  }

  staffRequests(
    query: { status?: string; page?: number; limit?: number } = {},
  ): Observable<{ staff_requests: StaffRequestRecord[]; meta: PageMeta }> {
    let params = new HttpParams();
    if (query.status) params = params.set('status', query.status);
    if (query.page) params = params.set('page', query.page);
    if (query.limit) params = params.set('limit', query.limit);
    return this.http.get<{ staff_requests: StaffRequestRecord[]; meta: PageMeta }>(
      `${this.base}/staff_requests`,
      {
        params,
      },
    );
  }

  createStaffRequest(payload: Record<string, unknown>): Observable<StaffRequestRecord> {
    return this.http.post<StaffRequestRecord>(`${this.base}/staff_requests`, {
      staff_request: payload,
    });
  }

  decideStaffRequest(
    id: number,
    decision: 'approve' | 'reject',
    reviewNote: string,
  ): Observable<StaffRequestRecord> {
    return this.http.post<StaffRequestRecord>(`${this.base}/staff_requests/${id}/${decision}`, {
      review_note: reviewNote,
    });
  }

  withdrawStaffRequest(id: number): Observable<StaffRequestRecord> {
    return this.http.post<StaffRequestRecord>(`${this.base}/staff_requests/${id}/withdraw`, {});
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

  orderReceipt(id: number): Observable<Blob> {
    return this.http.get(`${this.base}/orders/${id}/receipt`, { responseType: 'blob' });
  }

  applyDiscount(id: number, amountCents: number, reason: string): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${id}/discounts`, {
      amount_cents: amountCents,
      reason,
    });
  }

  addOrderLine(
    id: number,
    description: string,
    revenueCategory: string,
    unitPriceCents: number,
    quantity = 1,
  ): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${id}/line_items`, {
      description,
      revenue_category: revenueCategory,
      unit_price_cents: unitPriceCents,
      quantity,
    });
  }

  refundPayment(
    id: number,
    paymentId: number,
    amountCents: number,
    reason: string,
  ): Observable<Order> {
    return this.http.post<Order>(`${this.base}/orders/${id}/refunds`, {
      payment_id: paymentId,
      amount_cents: amountCents,
      reason,
    });
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
    return this.http.get<GiftCard>(`${this.base}/gift_cards/${encodeURIComponent(code)}`);
  }

  issueGiftCard(payload: Record<string, unknown>): Observable<GiftCard> {
    return this.http.post<GiftCard>(`${this.base}/gift_cards`, { gift_card: payload });
  }

  adjustGiftCard(id: number, amountCents: number, reason: string): Observable<GiftCard> {
    return this.http.post<GiftCard>(`${this.base}/gift_cards/${id}/adjust`, {
      amount_cents: amountCents,
      reason,
    });
  }

  voidGiftCard(id: number): Observable<GiftCard> {
    return this.http.post<GiftCard>(`${this.base}/gift_cards/${id}/void`, {});
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

  updateMembership(id: number, defaultServiceVariantId: number): Observable<MembershipRecord> {
    return this.http.patch<MembershipRecord>(`${this.base}/memberships/${id}`, {
      membership: { default_service_variant_id: defaultServiceVariantId },
    });
  }

  adjustMembershipCredits(
    id: number,
    amount: number,
    reason: string,
  ): Observable<MembershipRecord> {
    return this.http.post<MembershipRecord>(`${this.base}/memberships/${id}/adjust_credits`, {
      amount,
      reason,
    });
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

  earningStatement(id: number): Observable<import('../models').EarningStatement> {
    return this.http.get<import('../models').EarningStatement>(
      `${this.base}/earning_statements/${id}`,
    );
  }

  adjustEarningStatement(
    id: number,
    serviceDate: string,
    amountCents: number,
    reason: string,
  ): Observable<import('../models').EarningStatement> {
    return this.http.post<import('../models').EarningStatement>(
      `${this.base}/earning_statements/${id}/adjustments`,
      { service_date: serviceDate, amount_cents: amountCents, reason },
    );
  }

  earningStatementPdf(id: number): Observable<Blob> {
    return this.http.get(`${this.base}/earning_statements/${id}/pdf`, {
      responseType: 'blob',
    });
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

  earningLines(
    staffProfileId: number,
    from: string,
    to: string,
  ): Observable<{ lines: EarningLine[] }> {
    const params = new HttpParams()
      .set('staff_profile_id', staffProfileId)
      .set('from', from)
      .set('to', to);
    return this.http.get<{ lines: EarningLine[] }>(`${this.base}/earning_lines`, { params });
  }

  updateEarningLine(id: number, amountCents: number, note: string) {
    return this.http.patch<EarningLine>(`${this.base}/earning_lines/${id}`, {
      amount_cents: amountCents,
      note,
    });
  }

  // --- Administration (doc 05 §§4-6) ---

  createStaff(staff: Record<string, unknown>): Observable<StaffMember> {
    return this.http.post<StaffMember>(`${this.base}/staff`, { staff });
  }

  updateStaff(id: number, staff: Record<string, unknown>): Observable<StaffMember> {
    return this.http.patch<StaffMember>(`${this.base}/staff/${id}`, { staff });
  }

  offboardStaff(id: number, terminationDate?: string): Observable<StaffMember> {
    return this.http.post<StaffMember>(`${this.base}/staff/${id}/offboard`, {
      termination_date: terminationDate,
    });
  }

  qualifications(id: number): Observable<{ qualifications: Qualification[] }> {
    return this.http.get<{ qualifications: Qualification[] }>(
      `${this.base}/staff/${id}/qualifications`,
    );
  }

  setQualifications(
    id: number,
    serviceIds: number[],
  ): Observable<{ qualifications: Qualification[] }> {
    return this.http.put<{ qualifications: Qualification[] }>(
      `${this.base}/staff/${id}/qualifications`,
      { service_ids: serviceIds },
    );
  }

  sessionRates(id: number): Observable<{ session_rates: SessionRate[] }> {
    return this.http.get<{ session_rates: SessionRate[] }>(
      `${this.base}/staff/${id}/session_rates`,
    );
  }

  // BR-35: all six rungs together, effective-dated.
  setSessionRates(
    id: number,
    rates: { duration_minutes: number; rate_cents: number }[],
    effectiveFrom: string,
    note?: string,
  ): Observable<{ session_rates: SessionRate[] }> {
    return this.http.post<{ session_rates: SessionRate[] }>(
      `${this.base}/staff/${id}/session_rates`,
      { rates, effective_from: effectiveFrom, note },
    );
  }

  monthlyRate(id: number): Observable<{ monthly_rates: MonthlyRate[] }> {
    return this.http.get<{ monthly_rates: MonthlyRate[] }>(`${this.base}/staff/${id}/monthly_rate`);
  }

  setMonthlyRate(id: number, amountCents: number, effectiveFrom: string, note?: string) {
    return this.http.post<{ monthly_rates: MonthlyRate[] }>(
      `${this.base}/staff/${id}/monthly_rate`,
      {
        amount_cents: amountCents,
        effective_from: effectiveFrom,
        note,
      },
    );
  }

  // --- Roster ---

  roster(locationId: number, from: string, to: string): Observable<{ shifts: RosterShift[] }> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<{ shifts: RosterShift[] }>(`${this.base}/shifts`, { params });
  }

  createShift(shift: Record<string, unknown>): Observable<RosterShift> {
    return this.http.post<RosterShift>(`${this.base}/shifts`, { shift });
  }

  updateShift(id: number, shift: Record<string, unknown>): Observable<RosterShift> {
    return this.http.patch<RosterShift>(`${this.base}/shifts/${id}`, { shift });
  }

  deleteShift(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/shifts/${id}`);
  }

  publishShifts(shiftIds: number[]): Observable<{ published: RosterShift[] }> {
    return this.http.post<{ published: RosterShift[] }>(`${this.base}/shifts/publish`, {
      shift_ids: shiftIds,
    });
  }

  shiftBreaks(id: number): Observable<{ breaks: ShiftBreak[] }> {
    return this.http.get<{ breaks: ShiftBreak[] }>(`${this.base}/shifts/${id}/breaks`);
  }

  createShiftBreak(id: number, startsAt: string, endsAt: string, reason: string) {
    return this.http.post<ShiftBreak>(`${this.base}/shifts/${id}/breaks`, {
      starts_at: startsAt,
      ends_at: endsAt,
      reason,
    });
  }

  deleteShiftBreak(id: number, breakId: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/shifts/${id}/breaks/${breakId}`);
  }

  // --- Catalogue ---

  catalogue(): Observable<{ service_categories: { id: number; name: string }[] }> {
    return this.http.get<{ service_categories: { id: number; name: string }[] }>(
      `${this.base}/service_categories`,
    );
  }

  catalogueService(id: number): Observable<CatalogueService> {
    return this.http.get<CatalogueService>(`${this.base}/services/${id}`);
  }

  createService(service: Record<string, unknown>): Observable<CatalogueService> {
    return this.http.post<CatalogueService>(`${this.base}/services`, { service });
  }

  updateService(id: number, service: Record<string, unknown>): Observable<CatalogueService> {
    return this.http.patch<CatalogueService>(`${this.base}/services/${id}`, { service });
  }

  deleteService(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/services/${id}`);
  }

  setServiceActive(id: number, active: boolean): Observable<CatalogueService> {
    const action = active ? 'activate' : 'deactivate';
    return this.http.post<CatalogueService>(`${this.base}/services/${id}/${action}`, {});
  }

  createVariant(serviceId: number, variant: Record<string, unknown>): Observable<CatalogueVariant> {
    return this.http.post<CatalogueVariant>(`${this.base}/services/${serviceId}/service_variants`, {
      service_variant: variant,
    });
  }

  updateVariant(id: number, variant: Record<string, unknown>): Observable<CatalogueVariant> {
    return this.http.patch<CatalogueVariant>(`${this.base}/service_variants/${id}`, {
      service_variant: variant,
    });
  }

  variantPrices(variantId: number): Observable<{ prices: VariantPrice[] }> {
    return this.http.get<{ prices: VariantPrice[] }>(
      `${this.base}/service_variants/${variantId}/prices`,
    );
  }

  // BR-11: a new price is a new period, never an edit of the old one.
  setVariantPrice(
    variantId: number,
    locationId: number,
    priceCents: number,
    effectiveFrom: string,
  ) {
    return this.http.post<VariantPrice>(`${this.base}/service_variants/${variantId}/prices`, {
      location_id: locationId,
      price_cents: priceCents,
      effective_from: effectiveFrom,
    });
  }

  // --- Location, rooms, hours, closures ---

  updateLocation(id: number, location: Record<string, unknown>): Observable<Location> {
    return this.http.patch<Location>(`${this.base}/locations/${id}`, { location });
  }

  businessHours(id: number): Observable<{ business_hours: BusinessHour[] }> {
    return this.http.get<{ business_hours: BusinessHour[] }>(
      `${this.base}/locations/${id}/business_hours`,
    );
  }

  setBusinessHours(
    id: number,
    hours: BusinessHour[],
  ): Observable<{ business_hours: BusinessHour[] }> {
    return this.http.put<{ business_hours: BusinessHour[] }>(
      `${this.base}/locations/${id}/business_hours`,
      { business_hours: hours },
    );
  }

  closures(id: number): Observable<{ closures: Closure[] }> {
    return this.http.get<{ closures: Closure[] }>(`${this.base}/locations/${id}/closures`);
  }

  createClosure(id: number, date: string, reason?: string): Observable<Closure> {
    return this.http.post<Closure>(`${this.base}/locations/${id}/closures`, { date, reason });
  }

  deleteClosure(id: number, closureId: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/locations/${id}/closures/${closureId}`);
  }

  locationRooms(id: number): Observable<{ rooms: Room[] }> {
    return this.http.get<{ rooms: Room[] }>(`${this.base}/locations/${id}/rooms`);
  }

  createRoom(locationId: number, room: Record<string, unknown>): Observable<Room> {
    return this.http.post<Room>(`${this.base}/rooms`, { location_id: locationId, room });
  }

  updateRoom(id: number, room: Record<string, unknown>): Observable<Room> {
    return this.http.patch<Room>(`${this.base}/rooms/${id}`, { room });
  }

  roomBlocks(id: number): Observable<{ blocks: RoomBlock[] }> {
    return this.http.get<{ blocks: RoomBlock[] }>(`${this.base}/rooms/${id}/blocks`);
  }

  createRoomBlock(id: number, startsAt: string, endsAt: string, reason?: string) {
    return this.http.post<RoomBlock>(`${this.base}/rooms/${id}/blocks`, {
      starts_at: startsAt,
      ends_at: endsAt,
      reason,
    });
  }

  deleteRoomBlock(id: number, blockId: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/rooms/${id}/blocks/${blockId}`);
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

  ratingsReport(locationId: number, from: string, to: string): Observable<RatingsReport> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<RatingsReport>(`${this.base}/reports/ratings`, { params });
  }

  ratingAlerts(locationId: number, from: string, to: string): Observable<RatingAlertsReport> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<RatingAlertsReport>(`${this.base}/reports/ratings/alerts`, { params });
  }

  membershipReport(locationId: number, from: string, to: string): Observable<MembershipReport> {
    const params = new HttpParams().set('location_id', locationId).set('from', from).set('to', to);
    return this.http.get<MembershipReport>(`${this.base}/reports/membership`, { params });
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

  supersedeCareNote(id: number, body: string): Observable<CareNote> {
    return this.http.post<CareNote>(`${this.base}/care_notes/${id}/supersede`, { body });
  }

  managerPayouts(month: string): Observable<ManagerPayoutReport> {
    const params = new HttpParams().set('month', month);
    return this.http.get<ManagerPayoutReport>(`${this.base}/manager_payouts`, { params });
  }

  kioskQueue(locationId: number) {
    const params = new HttpParams().set('location_id', locationId);
    return this.http.get<{
      appointments: {
        id: number;
        reference: string;
        client_name: string;
        therapist: string;
        time: string;
      }[];
    }>(`${this.base}/ratings/kiosk_queue`, { params });
  }

  submitRating(payload: Record<string, unknown>) {
    return this.http.post(`${this.base}/ratings`, payload);
  }

  publicRating(token: string) {
    return this.http.get<{
      reference: string;
      therapist: string | null;
      location: string;
      starts_at: string;
      already_rated: boolean;
    }>(`${this.base}/public/ratings/${encodeURIComponent(token)}`);
  }

  submitPublicRating(token: string, payload: Record<string, unknown>) {
    return this.http.post(`${this.base}/public/ratings/${encodeURIComponent(token)}`, payload);
  }
}
