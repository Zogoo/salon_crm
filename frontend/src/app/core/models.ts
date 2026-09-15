export interface User {
  id: number;
  email: string;
  name: string;
  avatar_url: string | null;
  role: 'owner' | 'manager' | 'staff' | 'client';
  location_id: number | null;
  accessible_location_ids: number[];
  staff_profile_id: number | null;
  otp_enabled?: boolean;
}

export interface PageMeta {
  count: number;
  page: number;
  pages: number;
  limit: number;
  sort?: string;
  dir?: 'asc' | 'desc';
}

/** The list contract every large collection follows (see Listable on the API). */
export interface ListQuery {
  q?: string;
  page?: number;
  limit?: number;
  sort?: string;
  dir?: 'asc' | 'desc';
  [filter: string]: string | number | boolean | null | undefined;
}

export interface AuditLogRecord {
  id: number;
  action: string;
  auditable_type: string;
  auditable_id: number;
  actor: { id: number; name: string; email: string; role: string } | null;
  changes: Record<string, unknown>;
  ip_address: string | null;
  occurred_at: string;
}

export interface AuthResponse {
  token: string;
  user: User;
}

// --- Massagelab domain ---

export type Role = 'owner' | 'manager' | 'staff' | 'client';

export interface Location {
  id: number;
  name: string;
  code: string;
  timezone: string;
  opens_at: string;
  closes_at: string;
  buffer_minutes: number;
  slot_granularity_minutes: number;
  cancellation_window_hours: number;
  no_show_fee_percent: number;
  late_cancel_fee_percent: number;
  /** Most a Manager may discount an order, as a % of its services. */
  manager_discount_limit_percent: number;
  status: string;
  room_count: number;
  rooms?: Room[];
}

export interface Room {
  id: number;
  name: string;
  room_type: 'single' | 'couple' | 'three_table' | 'head_spa';
  client_capacity: number;
  exclusive?: boolean;
  position?: number;
  status?: string;
  location_id?: number;
}

export interface ServiceVariant {
  id: number;
  duration_minutes: number;
  price_cents: number;
  therapist_count: number;
  required_client_capacity: number;
  requires_room_type: string | null;
}

export interface Service {
  id: number;
  name: string;
  kind: 'standard' | 'add_on' | 'enhancement';
  category: string;
  category_position: number;
  variants: ServiceVariant[];
}

export interface StaffSummary {
  id: number;
  display_name: string;
}

export interface Slot {
  start_at: string;
  service_end_at: string;
  end_at: string;
  staff: StaffSummary[];
  room_available_count: number;
}

export interface Availability {
  location_id: number;
  timezone: string;
  duration_minutes: number;
  buffer_minutes: number;
  therapists_required: number;
  required_client_capacity: number;
  days: { date: string; slots: Slot[] }[];
}

export interface ClientRecord {
  id: number;
  first_name: string;
  last_name: string;
  full_name: string;
  phone: string;
  email: string | null;
  no_show_count: number;
  late_cancel_count: number;
  /** List rows only: derived from completed appointments. */
  last_visit_at?: string | null;
  visits_count?: number;
  member?: boolean;
  preferred_location?: { id: number; name: string } | null;
  date_of_birth?: string | null;
  preference?: {
    attention_areas: string | null;
    avoid_areas: string | null;
    pressure: string | null;
    other_requests: string | null;
  } | null;
  appointments?: {
    id: number;
    reference: string;
    starts_at: string;
    status: string;
    location: string;
    therapists: string[];
  }[];
}

export type AppointmentStatus =
  | 'pending_approval'
  | 'scheduled'
  | 'checked_in'
  | 'in_progress'
  | 'completed'
  | 'cancelled'
  | 'late_cancelled'
  | 'no_show';

export interface Appointment {
  id: number;
  reference: string;
  status: AppointmentStatus;
  starts_at: string;
  service_ends_at: string;
  ends_at: string;
  duration_minutes: number;
  room: { id: number; name: string };
  client: { id: number; full_name: string; phone: string };
  therapists: StaffSummary[];
  assignment_pending?: boolean;
  therapists_required?: number;
  total_price_cents: number;
  client_note: string | null;
  location?: { id: number; name: string };
  appointment_note?: string | null;
  fee_charged_cents?: number;
  /** Money taken before the visit, held for the client until checkout. */
  deposit?: Deposit | null;
  items?: {
    id: number;
    service_variant_id: number;
    name: string;
    kind: string;
    duration_minutes: number;
    price_cents: number;
  }[];
  preference?: ClientRecord['preference'];
}

export interface Deposit {
  id: number;
  amount_cents: number;
  method: PaymentMethod;
  status: 'held' | 'applied' | 'refunded' | 'forfeited';
  reference: string | null;
  fee_cents: number;
  refunded_cents: number;
  received_at: string;
}

export interface DayBoard {
  date: string;
  opens_at: string;
  closes_at: string;
  rooms: Room[];
  appointments: Appointment[];
}

export interface Dashboard {
  date: string;
  location: { id: number; name: string };
  appointments_today: number;
  completed_today: number;
  cancelled_today: number;
  no_shows_today: number;
  staff_working: number;
  staff_not_working: number;
  rooms_total: number;
  rooms_free_now: number;
  pending_approvals: number;
  revenue_booked_cents?: number;
}

export interface ApprovalRequest {
  id: number;
  status: string;
  pending_for_minutes: number;
  auto_approves_at: string;
  past_review_target: boolean;
  requested_therapist: StaffSummary;
  appointment: {
    id: number;
    reference: string;
    starts_at: string;
    status: string;
    client_name: string;
    location: string;
  };
}

export interface StaffMember {
  id: number;
  display_name: string;
  employee_code: string;
  location_id: number;
  status: string;
  engagement_type: string;
  role?: 'staff' | 'manager';
  location_name?: string;
  email?: string;
  hire_date?: string;
  services?: { id: number; name: string }[];
  can_edit_service_menu?: boolean;
  termination_date?: string | null;
  session_rates?: SessionRate[];
}

/** BR-35: effective-dated, so a row may be closed rather than current. */
export interface SessionRate {
  duration_minutes: number;
  rate_cents: number;
  effective_from: string;
  effective_to?: string | null;
  note?: string | null;
}

export interface MonthlyRate {
  amount_cents: number;
  effective_from: string;
  effective_to?: string | null;
  note?: string | null;
}

export interface Qualification {
  service_id: number;
  name: string;
  active: boolean;
}

export interface CatalogueService {
  id: number;
  name: string;
  kind: string;
  active: boolean;
  service_category_id: number;
  variants: CatalogueVariant[];
}

export interface CatalogueVariant {
  id: number;
  service_id?: number;
  duration_minutes: number;
  therapist_count: number;
  required_client_capacity: number;
  requires_room_type: string | null;
  active: boolean;
}

export interface VariantPrice {
  id: number;
  location_id: number;
  location: string;
  price_cents: number;
  effective_from: string;
  effective_to?: string | null;
}

export interface BusinessHour {
  id?: number;
  day_of_week: number;
  opens_at: string;
  closes_at: string;
}

export interface Closure {
  id: number;
  date: string;
  reason?: string | null;
}

export interface RoomBlock {
  id: number;
  starts_at: string;
  ends_at: string;
  reason?: string | null;
}

export interface RosterShift {
  id: number;
  staff_profile_id: number;
  display_name?: string;
  location_id: number;
  work_date: string;
  starts_at: string;
  ends_at: string;
  status: string;
  notes?: string | null;
}

export interface ShiftBreak {
  id: number;
  starts_at: string;
  ends_at: string;
  reason: string | null;
}

export interface StaffRequestRecord {
  id: number;
  kind: string;
  status: string;
  staff_profile_id: number;
  display_name: string;
  shift_id: number | null;
  /** The shift as it stands, in the location's wall clock. */
  shift?: { work_date: string; starts_at: string; ends_at: string } | null;
  requested_location?: { id: number; name: string } | null;
  requested_payload: Record<string, unknown>;
  note: string | null;
  review_note: string | null;
  reviewed_by_role: string | null;
  created_at: string;
}

export interface ShiftBoard {
  date: string;
  working: {
    id: number;
    work_date: string;
    staff_profile_id: number;
    display_name: string;
    starts_at: string;
    ends_at: string;
    notes: string | null;
  }[];
  not_working: { staff_profile_id: number; display_name: string }[];
}

// --- Money, gift cards, membership, earnings ---

export type PaymentMethod = 'card' | 'cash' | 'zelle' | 'online' | 'other';

export interface Order {
  id: number;
  number: string;
  status: string;
  kind: string;
  subtotal_cents: number;
  discount_cents: number;
  tip_cents: number;
  total_cents: number;
  paid_cents: number;
  redeemed_cents: number;
  credited_cents: number;
  outstanding_cents: number;
  /** A deposit still held for this visit; it already covers part of the bill. */
  deposit_cents: number;
  manual_discount_cents: number;
  manager_discount_limit_cents: number;
  appointment_id: number | null;
  client: { id: number; full_name: string } | null;
  line_items: {
    id: number;
    description: string;
    quantity: number;
    line_total_cents: number;
    revenue_category: string;
  }[];
  payments: {
    id: number;
    method: string;
    amount_cents: number;
    status: string;
    reference: string | null;
  }[];
  discounts: { id: number; kind: string; amount_cents: number; reason: string | null }[];
  gift_card_redemptions: { code: string; amount_cents: number }[];
  tips: { staff_profile_id: number; amount_cents: number; display_name: string }[];
}

export interface GiftCard {
  id: number;
  code: string;
  status: string;
  initial_value_cents: number;
  current_balance_cents: number;
  redeemable: boolean;
  expired: boolean;
  expires_at: string;
  sold_at: string;
  sold_at_location: { id: number; name: string };
  buyer: { client_id: number | null; name: string | null; phone: string | null };
  recipient: { client_id: number | null; name: string | null };
  ledger?: {
    kind: string;
    amount_cents: number;
    balance_after_cents: number;
    occurred_at: string;
    location_id: number | null;
    note: string | null;
  }[];
}

export interface MembershipRecord {
  id: number;
  status: string;
  price_cents: number;
  credits_balance: number;
  credits_cap: number;
  at_cap: boolean;
  client: { id: number; full_name: string; phone?: string };
  location: { id: number; name: string };
  enrolled_at?: string;
  current_period_end: string;
  cancellation_effective_at: string | null;
  default_service_variant_id?: number | null;
  cycles?: {
    period_start: string;
    charged_at: string | null;
    amount_cents: number;
    credit_granted: boolean;
    forfeited_to_cap: boolean;
  }[];
  credit_ledger?: {
    kind: string;
    amount: number;
    balance_after: number;
    occurred_at: string;
    cross_location_override: boolean;
  }[];
}

export interface EarningsReport {
  staff_profile_id: number;
  display_name: string;
  period: { from: string; to: string };
  sessions: { duration_minutes: number; quantity: number; earnings_cents: number }[];
  tips_cents: number;
  total_cents: number;
}

export interface EarningLine {
  id: number;
  service_date: string;
  source: string;
  duration_minutes: number | null;
  quantity: number;
  rate_cents: number | null;
  amount_cents: number;
  appointment_id: number | null;
  note: string | null;
}

export interface EarningPeriod {
  id: number;
  starts_on: string;
  ends_on: string;
  kind: string;
  status: string;
  locked: boolean;
  statements?: EarningStatement[];
}

export interface EarningStatement {
  id: number;
  staff_profile_id: number;
  display_name: string;
  total_sessions: number;
  service_earnings_cents: number;
  tips_cents: number;
  adjustments_cents: number;
  gross_amount_cents: number;
  locked: boolean;
  period?: { from: string; to: string };
  breakdown?: EarningsReport;
  adjustments?: {
    id: number;
    service_date: string;
    amount_cents: number;
    reason: string;
  }[];
}

export interface DailyRevenue {
  from: string;
  to: string;
  by_method: Record<string, number>;
  gross_service_revenue_cents: number;
  discounts_cents: number;
  service_revenue_cents: number;
  gift_card_liability_cents: number;
  membership_liability_cents: number;
  fees_cents: number;
  tips_cents: number;
  collected_cents: number;
  deposits_received_cents: number;
  deposits_held_cents: number;
}

export interface ClientLogRow {
  appointment_id: number;
  reference: string;
  time: string;
  client_name: string;
  therapists: string[];
  services: string[];
  duration_minutes: number;
  service_price_cents: number;
  tip_cents: number;
  total_paid_cents: number;
  payment_methods: string[];
}

export interface GiftCardLiability {
  as_of: string;
  total_outstanding_cents: number;
  card_count: number;
  by_location: Record<string, { count: number; cents: number }>;
  by_issue_month: Record<string, { count: number; cents: number }>;
  expired_but_spendable_cents: number;
}

export interface NoShowReport {
  from: string;
  to: string;
  appointments: number;
  no_shows: number;
  late_cancellations: number;
  no_show_rate: number;
  late_cancel_rate: number;
  fees_owed_cents: number;
  fees_collected_cents: number;
  by_weekday: Record<string, number>;
  by_therapist: Record<string, number>;
  by_channel: Record<string, number>;
}

export interface UtilizationReport {
  from: string;
  to: string;
  open_minutes_per_room: number;
  rooms: {
    room_id: number;
    name: string;
    booked_minutes: number;
    available_minutes: number;
    utilization_percent: number;
  }[];
  therapists: {
    staff_profile_id: number;
    display_name: string;
    booked_minutes: number;
    available_minutes: number;
    utilization_percent: number;
  }[];
}

export interface RetentionReport {
  from: string;
  to: string;
  clients_seen: number;
  new_clients: number;
  returning_clients: number;
  visits: number;
  average_visits_per_client: number;
  lapsed: { after_days: number; count: number; client_ids: number[] };
  top_clients: { client_id: number; full_name: string; visits: number; spend_cents: number }[];
}

export interface RatingsReport {
  from: string;
  to: string;
  count: number;
  average: number | null;
  distribution: Record<string, number>;
  recommend_rate: number | null;
  by_therapist: {
    staff_profile_id: number;
    display_name: string;
    count: number;
    average: number;
  }[];
}

export interface RatingAlertsReport {
  from: string;
  to: string;
  count: number;
  alerts: {
    id: number;
    score: number;
    feedback: string | null;
    improvement: string | null;
    threshold: number;
    location: string;
    therapist: string | null;
    appointment_id: number;
    created_at: string;
  }[];
}

export interface MembershipReport {
  from: string;
  to: string;
  active_members: number;
  credits_outstanding: number;
  at_cap: number;
  enrolled_in_period: number;
  pending_cancellations: number;
  credits_granted: number;
  credits_redeemed: number;
  cross_location_overrides: number;
  liability_cents: number;
}

export interface CareNote {
  id: number;
  staff_profile_id: number;
  body: string;
  created_at: string;
  author: string;
  supersedes_note_id: number | null;
}

export interface ManagerPayoutReport {
  month: string;
  total_cents: number;
  payouts: {
    id: number;
    staff_profile_id: number;
    display_name: string;
    location: string;
    amount_cents: number;
    status: string;
    paid_at: string | null;
  }[];
}

/** One row of a client's visit history (paged). */
export interface ClientVisit {
  id: number;
  reference: string;
  status: string;
  location: string;
  starts_at: string;
  therapists: string[];
  total_price_cents: number;
}

export interface ClientRating {
  id: number;
  appointment_id: number;
  score: number;
  comment: string | null;
  therapist: string | null;
  created_at: string;
}

export interface ClientGiftCard {
  id: number;
  code: string;
  initial_value_cents: number;
  balance_cents: number;
  status: string;
  sold_at: string;
  sold_at_location: string;
}

export interface ClientOrderHistory {
  id: number;
  number: string;
  status: string;
  location: string;
  total_cents: number;
  paid_cents: number;
  created_at: string;
}

export interface ClientHistorySummary {
  client_id: number;
  visits: number;
  lifetime_spend_cents: number;
  first_visit: string | null;
  last_visit: string | null;
  days_since_last_visit: number | null;
  favourite_service: string | null;
  favourite_therapist: string | null;
  no_show_count: number;
  late_cancel_count: number;
  cancel_count: number;
}

export interface PreferenceVersion {
  attention_areas: string | null;
  avoid_areas: string | null;
  pressure: string | null;
  other_requests: string | null;
  superseded_at: string;
}
