import { Component, OnInit, inject, signal } from '@angular/core';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';

import { ApprovalRequest } from '../../core/models';
import { MassagelabService } from '../../core/services/massagelab.service';
import { UiBanner, UiButton, UiCard, UiChip, UiEmpty, UiPage } from '../../ui';

/** FRS §5 — the therapist-request queue. 15-minute target, 45-minute backstop. */
@Component({
  selector: 'app-approvals',
  imports: [WallClockPipe, UiPage, UiCard, UiChip, UiEmpty, UiBanner, UiButton],
  template: `
    <ui-page
      title="Approvals"
      sub="A client asked for a specific therapist. Review within 15 minutes where you can — anything still pending at 45 minutes is approved automatically, provided that therapist is still free."
    >
      @if (error()) { <ui-banner tone="error">{{ error() }}</ui-banner> }

      <ui-card>
        @if (requests().length) {
          <ul class="list" data-testid="approval-list">
            @for (r of requests(); track r.id) {
              <li class="item" [class.item--late]="r.past_review_target">
                <div class="item__who">
                  <strong>{{ r.appointment.client_name }}</strong>
                  <small>{{ r.appointment.reference }}</small>
                  <small>
                    {{ r.appointment.starts_at | wallClock: 'datetime' }} ·
                    {{ r.appointment.location }} · asked for
                    {{ r.requested_therapist.display_name }}
                  </small>
                </div>

                <ui-chip
                  [tone]="r.past_review_target ? 'warning' : 'info'"
                  [attr.data-testid]="'age-' + r.id"
                >
                  waiting {{ r.pending_for_minutes }} min
                </ui-chip>

                <div class="item__actions">
                  <ui-button icon="check" (click)="decide(r, 'approve')"
                             [attr.data-testid]="'approve-' + r.id">Approve</ui-button>
                  <ui-button variant="danger" icon="close" (click)="decide(r, 'reject')"
                             [attr.data-testid]="'reject-' + r.id">Reject</ui-button>
                </div>
              </li>
            }
          </ul>
        } @else {
          <ui-empty
            icon="task_alt"
            title="Nothing waiting"
            hint="Requests appear here the moment a client asks for a named therapist."
            data-testid="approvals-empty"
          />
        }
      </ui-card>
    </ui-page>
  `,
  styles: `
    @use '../../../styles/tokens' as *;

    .list { display: flex; flex-direction: column; gap: var(--sp-2); }

    .item {
      display: flex;
      align-items: center;
      gap: var(--sp-3);
      flex-wrap: wrap;
      padding: var(--sp-3);
      background: var(--md-surface-container-low);
      border-radius: var(--md-shape-sm);
    }

    // Past the 15-minute review target: a border rather than a colour swap, so
    // it reads as "look at this one first", not as an error.
    .item--late { box-shadow: inset 3px 0 0 var(--md-warning); }

    .item__who {
      display: flex;
      flex-direction: column;
      min-width: 0;
      margin-right: auto;
      strong { @include type-body-lg; }
      small { @include type-body-sm; color: var(--md-on-surface-variant); }
    }

    .item__actions { display: flex; gap: var(--sp-2); flex-wrap: wrap; }
  `,
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
