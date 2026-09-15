import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { RosterShift, StaffRequestRecord } from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';
import {
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiField,
  UiPage,
  humanise,
  statusTone,
} from '../../ui';

const MESSAGES: Record<string, string> = {
  shift_required: 'Choose which of your shifts you want changed.',
  location_required: 'Choose the location you want to move to.',
  owner_approval_required: 'Only the Owner can approve a move to another location.',
  would_orphan_appointments:
    'That change would leave booked appointments without a therapist. Move them first.',
  has_future_appointments:
    'This therapist still has appointments booked here. Move or reassign them first.',
  already_reviewed: 'That request has already been reviewed.',
};

@Component({
  selector: 'app-staff-requests',
  imports: [
    FormsModule,
    WallClockPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiBanner,
  ],
  templateUrl: './staff-requests.html',
  styleUrls: ['../../ui/layouts.scss', './staff-requests.scss'],
})
export class StaffRequestsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly ctx = inject(LocationContextService);
  private readonly clock = new WallClockPipe();
  protected readonly auth = inject(AuthService);

  protected readonly requests = signal<StaffRequestRecord[]>([]);
  protected readonly shiftsAhead = signal<RosterShift[]>([]);
  protected readonly directory = signal<{ id: number; name: string }[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly isStaff = computed(() => this.auth.user()?.role === 'staff');
  protected readonly otherLocations = computed(() =>
    this.directory().filter((l) => l.id !== this.ctx.current()?.id),
  );

  protected form = this.emptyForm();
  protected reviewNotes: Record<number, string> = {};
  protected humanStatus = humanise;
  protected tone = statusTone;

  ngOnInit(): void {
    this.reload();
    if (!this.isStaff()) return;
    this.api.locationDirectory().subscribe({
      next: ({ locations }) => this.directory.set(locations),
    });
    void this.ctx.load().then(() => this.loadShifts());
  }

  protected reload(): void {
    this.api.staffRequests().subscribe({
      next: ({ staff_requests }) => this.requests.set(staff_requests),
      error: () => this.error.set('Could not load staff requests.'),
    });
  }

  protected kindLabel(kind: string): string {
    return kind === 'location_change' ? 'Move to another location' : 'Shift change';
  }

  protected shiftLabel(shift: RosterShift): string {
    return `${this.clock.transform(shift.starts_at, 'date')} · ${this.clock.transform(shift.starts_at)}–${this.clock.transform(shift.ends_at)}`;
  }

  /** What was asked for, in words — never an id. */
  protected detail(request: StaffRequestRecord): string {
    if (request.kind === 'location_change') {
      return request.requested_location
        ? `Move to ${request.requested_location.name}`
        : 'Move to another location';
    }
    const shift = request.shift;
    const payload = request.requested_payload as { starts_at?: string; ends_at?: string };
    const wanted = `${payload.starts_at || shift?.starts_at || '?'}–${payload.ends_at || shift?.ends_at || '?'}`;
    return shift
      ? `${this.clock.transform(`${shift.work_date}T00:00`, 'date')}: ${shift.starts_at}–${shift.ends_at} → ${wanted}`
      : `Asked for ${wanted}`;
  }

  /** Picking a shift starts the new times from its current ones. */
  protected chooseShift(id: number | null): void {
    const shift = this.shiftsAhead().find((s) => s.id === id);
    this.form.shift_id = shift?.id ?? null;
    this.form.starts_at = shift ? this.clock.transform(shift.starts_at) : '';
    this.form.ends_at = shift ? this.clock.transform(shift.ends_at) : '';
  }

  protected submit(): void {
    this.error.set(null);
    this.notice.set(null);
    const shiftChange = this.form.kind === 'shift_change';
    if (shiftChange && !this.form.shift_id) {
      this.error.set(MESSAGES['shift_required']);
      return;
    }
    if (!shiftChange && !this.form.location_id) {
      this.error.set(MESSAGES['location_required']);
      return;
    }

    this.api
      .createStaffRequest({
        kind: this.form.kind,
        shift_id: shiftChange ? this.form.shift_id : null,
        note: this.form.note.trim(),
        requested_payload: shiftChange
          ? { starts_at: this.form.starts_at, ends_at: this.form.ends_at }
          : { location_id: this.form.location_id },
      })
      .subscribe({
        next: () => {
          this.notice.set('Request sent. You will see the outcome here.');
          this.form = this.emptyForm();
          this.reload();
        },
        error: (err) => this.error.set(this.message(err, 'Could not send the request.')),
      });
  }

  protected decide(request: StaffRequestRecord, decision: 'approve' | 'reject'): void {
    this.error.set(null);
    this.api
      .decideStaffRequest(request.id, decision, this.reviewNotes[request.id] ?? '')
      .subscribe({
        next: () => {
          this.notice.set(`Request ${decision === 'approve' ? 'approved' : 'rejected'}.`);
          this.reload();
        },
        error: (err) => this.error.set(this.message(err, 'Could not review the request.')),
      });
  }

  protected withdraw(request: StaffRequestRecord): void {
    this.api.withdrawStaffRequest(request.id).subscribe({ next: () => this.reload() });
  }

  private loadShifts(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    const from = todayIn(loc.timezone);
    const to = new Date(`${from}T12:00:00Z`);
    to.setUTCDate(to.getUTCDate() + 28);
    this.api.roster(loc.id, from, to.toISOString().slice(0, 10)).subscribe({
      next: ({ shifts }) => this.shiftsAhead.set(shifts.filter((s) => s.status === 'published')),
      error: () => this.shiftsAhead.set([]),
    });
  }

  private emptyForm() {
    return {
      kind: 'shift_change' as 'shift_change' | 'location_change',
      shift_id: null as number | null,
      note: '',
      starts_at: '',
      ends_at: '',
      location_id: null as number | null,
    };
  }

  private message(err: unknown, fallback: string): string {
    const code = (err as { error?: { error?: { code?: string } } })?.error?.error?.code;
    return (code && MESSAGES[code]) || fallback;
  }
}
