import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { StaffRequestRecord } from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { MassagelabService } from '../../core/services/massagelab.service';
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
  styleUrl: '../../ui/layouts.scss',
})
export class StaffRequestsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly auth = inject(AuthService);
  protected readonly requests = signal<StaffRequestRecord[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly isStaff = computed(() => this.auth.user()?.role === 'staff');
  protected form = {
    kind: 'shift_change',
    shift_id: null as number | null,
    note: '',
    starts_at: '',
    ends_at: '',
    location_id: null as number | null,
  };
  protected reviewNotes: Record<number, string> = {};
  protected humanStatus = humanise;
  protected tone = statusTone;

  ngOnInit(): void {
    this.reload();
  }

  protected reload(): void {
    this.api.staffRequests().subscribe({
      next: ({ staff_requests }) => this.requests.set(staff_requests),
      error: () => this.error.set('Could not load staff requests.'),
    });
  }

  protected submit(): void {
    const requested_payload =
      this.form.kind === 'shift_change'
        ? { starts_at: this.form.starts_at, ends_at: this.form.ends_at }
        : { location_id: this.form.location_id };
    this.api
      .createStaffRequest({
        kind: this.form.kind,
        shift_id: this.form.shift_id,
        note: this.form.note,
        requested_payload,
      })
      .subscribe({
        next: () => {
          this.notice.set('Request submitted.');
          this.reload();
        },
        error: () => this.error.set('Could not submit the request.'),
      });
  }

  protected decide(request: StaffRequestRecord, decision: 'approve' | 'reject'): void {
    this.api
      .decideStaffRequest(request.id, decision, this.reviewNotes[request.id] ?? '')
      .subscribe({
        next: () => {
          this.notice.set(`Request ${decision}d.`);
          this.reload();
        },
        error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not review the request.'),
      });
  }

  protected withdraw(request: StaffRequestRecord): void {
    this.api.withdrawStaffRequest(request.id).subscribe({ next: () => this.reload() });
  }
}
