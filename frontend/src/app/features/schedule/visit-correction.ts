import { Component, OnInit, computed, inject, input, output, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { Appointment, Order, PaymentMethod, PaymentPart, StaffSummary } from '../../core/models';
import { MassagelabService } from '../../core/services/massagelab.service';
import { PaymentSplit, TENDER_LABELS } from '../../shared/payment-split';
import { UiBanner, UiButton, UiDialog, UiField } from '../../ui';

const MESSAGES: Record<string, string> = {
  reason_required: 'Say why the visit is being corrected — it is kept with the change.',
  period_locked: 'That pay period is locked, so this visit can no longer be changed.',
  visit_has_refunds:
    'Money has already been refunded on this visit, so it cannot be corrected here.',
  visit_not_settled: 'This visit is not closed yet — finish it at checkout instead.',
  wrong_therapist_count: 'Choose the number of therapists this service needs.',
  therapist_not_qualified: 'That therapist is not qualified for this service.',
  therapist_unavailable: 'That therapist was with another client at that time.',
  gift_card_not_found: 'No gift card with that code.',
  insufficient_balance: 'Not enough left on that gift card.',
  deposit_invalid: 'Enter a deposit amount above $0.',
};

/**
 * Addendum §2: correct a completed, paid visit — who did it, the tip, the
 * transaction fee, the deposit and how it was paid.
 *
 * Everything is on one form and saved together, with the reason, so the
 * figures the reports and earnings show are always the corrected ones and the
 * original stays on record beside it.
 */
@Component({
  selector: 'app-visit-correction',
  imports: [FormsModule, DecimalPipe, UiDialog, UiField, UiButton, UiBanner, PaymentSplit],
  template: `
    <ui-dialog
      heading="Correct this visit"
      [sub]="appointment().client.full_name + ' · ' + appointment().reference"
      size="lg"
      (closed)="closed.emit()"
      data-testid="visit-correction"
    >
      @if (error()) {
        <ui-banner tone="error" data-testid="correction-error">{{ error() }}</ui-banner>
      }
      @if (order(); as o) {
        <div class="form-grid">
          @for (slot of therapistSlots(); track $index; let i = $index) {
            <ui-field [label]="therapistSlots().length > 1 ? 'Therapist ' + (i + 1) : 'Therapist'">
              <select
                [ngModel]="staffIds()[i]"
                (ngModelChange)="setStaff(i, $event)"
                [attr.data-testid]="'correction-staff-' + i"
              >
                @for (s of staffOptions(); track s.id) {
                  <option [ngValue]="s.id">{{ s.display_name }}</option>
                }
              </select>
            </ui-field>
          }
          <ui-field label="Tip" hint="In dollars. All of it goes to the therapist.">
            <input
              type="number"
              min="0"
              step="0.01"
              [ngModel]="tipDollars()"
              (ngModelChange)="tipDollars.set($event)"
              data-testid="correction-tip"
            />
          </ui-field>
          <ui-field label="Transaction fee" hint="In dollars.">
            <input
              type="number"
              min="0"
              step="0.01"
              [ngModel]="feeDollars()"
              (ngModelChange)="feeDollars.set($event)"
              data-testid="correction-fee"
            />
          </ui-field>
          @if (depositPayment()) {
            <ui-field label="Deposit" hint="Taken before the visit. In dollars.">
              <input
                type="number"
                min="0.01"
                step="0.01"
                [ngModel]="depositDollars()"
                (ngModelChange)="depositDollars.set($event)"
                data-testid="correction-deposit"
              />
            </ui-field>
            <ui-field label="Deposit paid by">
              <select [(ngModel)]="depositMethod" data-testid="correction-deposit-method">
                @for (m of depositMethods; track m) {
                  <option [value]="m">{{ labels[m] }}</option>
                }
              </select>
            </ui-field>
          }
        </div>

        <section class="correction__pay">
          <h3 class="sub-head">How the client paid</h3>
          <p class="sub-hint">
            New total \${{ newTotalCents() / 100 | number: '1.2-2' }}
            @if (depositCents()) {
              — \${{ depositCents() / 100 | number: '1.2-2' }} deposit
            }
            leaves \${{ dueCents() / 100 | number: '1.2-2' }} to account for.
          </p>
          @if (dueCents() > 0) {
            <app-payment-split
              [dueCents]="dueCents()"
              [initial]="initialParts()"
              (changed)="payment.set($event)"
            />
          }
        </section>

        <ui-field label="Reason for the correction" hint="Kept with the change in the audit log.">
          <input [(ngModel)]="reason" data-testid="correction-reason" />
        </ui-field>
      }
      <div dialogActions>
        <ui-button variant="text" (click)="closed.emit()">Cancel</ui-button>
        <ui-button
          icon="save"
          (click)="save()"
          [disabled]="saving() || !canSave()"
          data-testid="correction-save"
        >
          {{ saving() ? 'Saving…' : 'Save correction' }}
        </ui-button>
      </div>
    </ui-dialog>
  `,
  styles: `
    .correction__pay {
      display: flex;
      flex-direction: column;
      gap: var(--sp-2);
    }
  `,
  styleUrls: ['../../ui/layouts.scss'],
})
export class VisitCorrection implements OnInit {
  private readonly api = inject(MassagelabService);

  readonly appointment = input.required<Appointment>();
  /** Therapists who can be named: those on the roster that day, plus whoever is on it now. */
  readonly staff = input<StaffSummary[]>([]);
  readonly saved = output<Appointment>();
  readonly closed = output<void>();

  protected readonly labels = TENDER_LABELS;
  protected readonly depositMethods: PaymentMethod[] = ['card', 'cash', 'zelle', 'venmo', 'other'];
  protected readonly order = signal<Order | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly saving = signal(false);
  protected readonly staffIds = signal<number[]>([]);
  protected readonly tipDollars = signal(0);
  protected readonly feeDollars = signal(0);
  protected readonly depositDollars = signal(0);
  protected readonly payment = signal<{ parts: PaymentPart[]; valid: boolean }>({
    parts: [],
    valid: false,
  });
  protected readonly initialParts = signal<PaymentPart[] | null>(null);
  protected depositMethod: PaymentMethod = 'card';
  protected reason = '';

  protected readonly therapistSlots = computed(() =>
    Array.from({ length: Math.max(this.appointment().therapists_required ?? 1, 1) }),
  );

  protected readonly staffOptions = computed(() => {
    const byId = new Map<number, StaffSummary>();
    for (const s of [...this.appointment().therapists, ...this.staff()]) byId.set(s.id, s);
    return [...byId.values()].sort((a, b) => a.display_name.localeCompare(b.display_name));
  });

  protected readonly depositPayment = computed(() =>
    this.order()?.payments.find((p) => p.processing === 'deposit' && p.status === 'captured'),
  );

  protected readonly depositCents = computed(() =>
    this.depositPayment() ? Math.round((this.depositDollars() || 0) * 100) : 0,
  );

  /** The bill with the new tip and fee; services and discounts do not change here. */
  protected readonly newTotalCents = computed(() => {
    const o = this.order();
    if (!o) return 0;
    const base = o.total_cents - o.tip_cents - o.transaction_fee_cents;
    return (
      base + Math.round((this.tipDollars() || 0) * 100) + Math.round((this.feeDollars() || 0) * 100)
    );
  });

  protected readonly dueCents = computed(() =>
    Math.max(this.newTotalCents() - this.depositCents(), 0),
  );

  protected readonly canSave = computed(
    () =>
      !!this.order() &&
      (this.dueCents() === 0 || this.payment().valid) &&
      this.staffIds().every((id) => !!id),
  );

  ngOnInit(): void {
    const appt = this.appointment();
    this.staffIds.set(appt.therapists.map((t) => t.id));
    const orderId = appt.order?.id;
    if (!orderId) return;
    this.api.order(orderId).subscribe({
      next: (o) => {
        this.order.set(o);
        this.tipDollars.set(o.tip_cents / 100);
        this.feeDollars.set(o.transaction_fee_cents / 100);
        const deposit = o.payments.find(
          (p) => p.processing === 'deposit' && p.status === 'captured',
        );
        if (deposit) {
          this.depositDollars.set(deposit.amount_cents / 100);
          this.depositMethod = deposit.method as PaymentMethod;
        }
        // Start from what was actually taken, so a one-line fix is a one-line edit.
        this.initialParts.set([
          ...o.payments
            .filter((p) => p.status === 'captured' && p.processing !== 'deposit')
            .map((p) => ({ method: p.method as PaymentMethod, amount_cents: p.amount_cents })),
          ...o.gift_card_redemptions.map((g) => ({
            method: 'gift_card' as const,
            amount_cents: g.amount_cents,
            code: g.code,
          })),
        ]);
      },
      error: () => this.error.set('Could not open the payments for this visit.'),
    });
  }

  protected setStaff(index: number, id: number): void {
    this.staffIds.update((ids) => ids.map((v, i) => (i === index ? id : v)));
  }

  protected save(): void {
    if (!this.reason.trim()) {
      this.error.set(MESSAGES['reason_required']);
      return;
    }
    this.saving.set(true);
    this.error.set(null);
    this.api
      .correctVisit(this.appointment().id, {
        reason: this.reason.trim(),
        staff_profile_ids: this.staffIds(),
        tip_cents: Math.round((this.tipDollars() || 0) * 100),
        transaction_fee_cents: Math.round((this.feeDollars() || 0) * 100),
        payments: this.dueCents() > 0 ? this.payment().parts : [],
        ...(this.depositPayment()
          ? { deposit: { amount_cents: this.depositCents(), method: this.depositMethod } }
          : {}),
      })
      .subscribe({
        next: (appt) => {
          this.saving.set(false);
          this.saved.emit(appt);
        },
        error: (err) => {
          this.saving.set(false);
          const body = err?.error?.error;
          this.error.set(
            body?.code === 'split_total_mismatch'
              ? `The payments must add up to exactly $${((body.details?.due_cents ?? 0) / 100).toFixed(2)}.`
              : (MESSAGES[body?.code] ?? body?.code ?? 'Could not save the correction.'),
          );
        },
      });
  }
}
