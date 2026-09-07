import { Component, OnInit, inject, signal } from '@angular/core';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';

import { ApprovalRequest } from '../../core/models';
import { MassagelabService } from '../../core/services/massagelab.service';

/** FRS §5 — the therapist-request queue. 15-minute target, 45-minute backstop. */
@Component({
  selector: 'app-approvals',
  imports: [WallClockPipe],
  template: `
    <section class="approvals">
      <h1>Therapist requests</h1>
      <p class="muted">
        Review within 15 minutes where you can. Anything still pending at 45 minutes is approved
        automatically, provided the therapist is still free.
      </p>

      @if (error()) {
        <p class="alert" role="alert">{{ error() }}</p>
      }

      @if (requests().length) {
        <ul class="list" data-testid="approval-list">
          @for (r of requests(); track r.id) {
            <li class="item" [class.item--late]="r.past_review_target">
              <div>
                <strong>{{ r.appointment.client_name }}</strong>
                <span class="muted"> · {{ r.appointment.reference }}</span>
                <div class="muted">
                  {{ r.appointment.starts_at | wallClock: 'datetime' }} ·
                  {{ r.appointment.location }} · requested {{ r.requested_therapist.display_name }}
                </div>
              </div>
              <div class="age" [attr.data-testid]="'age-' + r.id">
                {{ r.pending_for_minutes }} min
              </div>
              <div class="actions">
                <button type="button" class="btn" (click)="decide(r, 'approve')"
                        [attr.data-testid]="'approve-' + r.id">Approve</button>
                <button type="button" class="btn btn--danger" (click)="decide(r, 'reject')"
                        [attr.data-testid]="'reject-' + r.id">Reject</button>
              </div>
            </li>
          }
        </ul>
      } @else {
        <p class="muted" data-testid="approvals-empty">Nothing waiting.</p>
      }
    </section>
  `,
  styles: [
    `
      .approvals { display: flex; flex-direction: column; gap: .75rem; }
      h1 { font-size: 1.15rem; margin: 0; }
      .list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: .5rem; }
      .item {
        display: flex; align-items: center; gap: 1rem; padding: .7rem .9rem;
        border: 1px solid var(--border, #e2e4e9); border-radius: .5rem; background: #fff;
      }
      .item--late { border-color: #e6b800; background: #fffdf3; }
      .age { margin-left: auto; font-variant-numeric: tabular-nums; font-weight: 650; }
      .actions { display: flex; gap: .4rem; }
      .muted { color: #6b7280; font-size: .85rem; }
      .alert { background: #fdecec; border: 1px solid #f5c2c2; color: #7a1c1c; padding: .6rem .75rem; border-radius: .4rem; }
      .btn { border: 1px solid transparent; background: #1f6feb; color: #fff; padding: .35rem .7rem; border-radius: .4rem; cursor: pointer; font-size: .85rem; }
      .btn--danger { background: #b4232a; }
    `,
  ],
})
export class ApprovalsPage implements OnInit {
  private readonly api = inject(MassagelabService);

  protected readonly requests = signal<ApprovalRequest[]>([]);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    this.reload();
  }

  protected reload(): void {
    this.api.approvalRequests().subscribe({
      next: ({ approval_requests }) => this.requests.set(approval_requests),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load requests'),
    });
  }

  protected decide(req: ApprovalRequest, decision: 'approve' | 'reject'): void {
    this.api.decideApproval(req.id, decision).subscribe({
      next: () => this.reload(),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not update the request'),
    });
  }
}
