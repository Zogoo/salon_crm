export interface User {
  id: number;
  email: string;
  name: string;
  avatar_url: string | null;
  role: 'owner' | 'manager' | 'staff' | 'client';
  location_id: number | null;
  accessible_location_ids: number[];
  staff_profile_id: number | null;
}

export interface Note {
  id: number;
  title: string;
  body: string | null;
  created_at: string;
  updated_at: string;
}

export interface PageMeta {
  count: number;
  page: number;
  pages: number;
  limit: number;
}

export interface NotesPage {
  notes: Note[];
  meta: PageMeta;
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
  room_count: number;
  rooms?: Room[];
}

export interface Room {
  id: number;
  name: string;
  room_type: 'single' | 'couple' | 'three_table' | 'head_spa';
  client_capacity: number;
  exclusive?: boolean;
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
  total_price_cents: number;
  client_note: string | null;
  location?: { id: number; name: string };
  appointment_note?: string | null;
  fee_charged_cents?: number;
  items?: { id: number; name: string; kind: string; duration_minutes: number; price_cents: number }[];
  preference?: ClientRecord['preference'];
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
  email?: string;
  hire_date?: string;
  services?: { id: number; name: string }[];
  session_rates?: { duration_minutes: number; rate_cents: number; effective_from: string }[];
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
