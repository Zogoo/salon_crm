import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { Order, PaymentMethod } from '../../core/models';
import { AuthService } from '../../core/services/auth.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import {
  ConfirmService,
  UiBanner,
  UiButton,
  UiCard,
  UiEmpty,
  UiField,
  UiPage,
  UiTable,
  humanise,
} from '../../ui';

/**
 * FRS §5, §7, §21 — the checkout.
 *
 * Release 1 *records* payments; it does not process them (doc 08 §1). What the
 * card terminal, the drawer or a Zelle transfer already did gets typed in here.
 */
@Component({
  selector: 'app-checkout',
  imports: [
    FormsModule,
    DecimalPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiEmpty,
    UiTable,
    UiBanner,
  ],
  templateUrl: './checkout.html',
  // Shared list-and-detail layout first, then what is specific here.
  styleUrls: ['../../ui/layouts.scss', './checkout.scss'],
})
export class CheckoutPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly route = inject(ActivatedRoute);
  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly confirm = inject(ConfirmService);

  protected readonly order = signal<Order | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly busy = signal(false);

  protected humanStatus(value: string) {
    return humanise(value);
  }

  protected readonly methods: PaymentMethod[] = ['card', 'cash', 'zelle', 'online', 'other'];
  protected method: PaymentMethod = 'card';
  protected amountDollars = 0;
  protected giftCardCode = '';
  protected giftCardDollars = 0;
  protected tipDollars = 0;
  protected discountDollars = 0;
  protected discountReason = '';
  protected manualLine = {
    description: '',
    category: 'service',
    quantity: 1,
    dollars: 0,
  };

  // FRS §21: the terminal prompts 20 / 25 / 30 or a custom amount.
  protected readonly tipPresets = [20, 25, 30];

  protected readonly outstandingDollars = computed(
    () => (this.order()?.outstanding_cents ?? 0) / 100,
  );
  protected readonly settled = computed(() => this.order()?.status === 'paid');
  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');

  /** Owner without limit; a Manager up to the location's share of the services. */
  protected readonly discountSub = computed(() => {
    const o = this.order();
    if (this.isOwner() || !o) return 'Recorded in the order ledger with your name and the reason.';
    const left = Math.max(0, o.manager_discount_limit_cents - o.manual_discount_cents);
    return `You can discount up to $${(left / 100).toFixed(2)} more on this order. Above that, ask the Owner.`;
  });

  ngOnInit(): void {
    const appointmentId = Number(this.route.snapshot.paramMap.get('appointmentId'));
    if (!appointmentId) return;
    this.api.openOrder(appointmentId).subscribe({
      next: (order) => this.accept(order),
      error: (err) => this.error.set(this.messageFrom(err)),
    });
  }

  protected tipFromPercent(percent: number): void {
    const base = this.order()?.subtotal_cents ?? 0;
    this.tipDollars = Math.round((base * percent) / 100) / 100;
    this.applyTip();
  }

  protected applyTip(): void {
    const order = this.order();
    if (!order) return;
    this.run(this.api.setTip(order.id, Math.round(this.tipDollars * 100)));
  }

  protected pay(): void {
    const order = this.order();
    if (!order) return;
    const cents = Math.round(this.amountDollars * 100);
    if (cents <= 0) return;
    this.run(this.api.addPayment(order.id, this.method, cents));
  }

  protected payRemainder(): void {
    const order = this.order();
    if (!order || order.outstanding_cents <= 0) return;
    this.run(this.api.addPayment(order.id, this.method, order.outstanding_cents));
  }

  protected redeem(): void {
    const order = this.order();
    if (!order || !this.giftCardCode) return;
    this.run(
      this.api.redeemGiftCard(
        order.id,
        this.giftCardCode.trim(),
        Math.round(this.giftCardDollars * 100),
      ),
    );
  }

  protected applyMembership(): void {
    const order = this.order();
    if (!order) return;
    this.run(this.api.applyMembershipCredit(order.id));
  }

  protected applyMembershipOverride(): void {
    const order = this.order();
    if (!order) return;
    this.run(this.api.applyMembershipCredit(order.id, true));
  }

  /**
   * BR-23: a payment cannot be edited, so a mis-keyed amount is corrected by
   * voiding it and recording the right one. Owner only — the API enforces it.
   */
  protected async voidPayment(paymentId: number): Promise<void> {
    const order = this.order();
    const payment = order?.payments.find((p) => p.id === paymentId);
    if (!order || !payment) return;
    const { confirmed, value } = await this.confirm.ask({
      title: `Void this $${(payment.amount_cents / 100).toFixed(2)} ${humanise(payment.method).toLowerCase()} payment?`,
      message:
        'It stays on the record, struck through, and the amount becomes outstanding again. Use this for a payment keyed in by mistake — money actually returned is a refund.',
      confirmLabel: 'Void payment',
      tone: 'danger',
      field: { label: 'Reason', required: true, placeholder: 'e.g. Entered the wrong amount' },
    });
    if (!confirmed) return;
    this.run(this.api.voidPayment(order.id, paymentId, value));
  }

  protected discount(): void {
    const order = this.order();
    const cents = Math.round(this.discountDollars * 100);
    if (!order || cents <= 0 || !this.discountReason.trim()) return;
    this.run(this.api.applyDiscount(order.id, cents, this.discountReason.trim()));
  }

  protected addLine(): void {
    const order = this.order();
    const cents = Math.round(this.manualLine.dollars * 100);
    if (!order || !this.manualLine.description.trim() || cents < 0) return;
    this.run(
      this.api.addOrderLine(
        order.id,
        this.manualLine.description.trim(),
        this.manualLine.category,
        cents,
        this.manualLine.quantity,
      ),
    );
  }

  protected async refund(paymentId: number): Promise<void> {
    const order = this.order();
    const payment = order?.payments.find((p) => p.id === paymentId);
    if (!order || !payment) return;
    const max = payment.amount_cents / 100;
    const { confirmed, values } = await this.confirm.ask({
      title: 'Refund a payment',
      message: `Record money given back from this ${humanise(payment.method).toLowerCase()} payment of $${max.toFixed(2)}. The payment itself is never edited.`,
      confirmLabel: 'Record refund',
      tone: 'danger',
      fields: [
        {
          key: 'amount',
          label: 'Amount to refund',
          type: 'number',
          required: true,
          max,
          initial: max.toFixed(2),
          hint: `Up to $${max.toFixed(2)}.`,
        },
        {
          key: 'reason',
          label: 'Reason',
          required: true,
          placeholder: 'e.g. Client unhappy with the service',
        },
      ],
    });
    if (!confirmed) return;
    this.run(
      this.api.refundPayment(
        order.id,
        paymentId,
        Math.round(Number(values['amount']) * 100),
        values['reason'],
      ),
    );
  }

  protected receipt(): void {
    const order = this.order();
    if (!order) return;
    this.api.orderReceipt(order.id).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        window.open(url, '_blank', 'noopener');
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
      },
      error: () => this.error.set('Could not open the receipt'),
    });
  }

  protected settle(): void {
    const order = this.order();
    if (!order) return;
    this.run(this.api.settleOrder(order.id));
  }

  protected backToBoard(): void {
    void this.router.navigate(['/schedule']);
  }

  private run(obs: ReturnType<MassagelabService['settleOrder']>): void {
    this.busy.set(true);
    this.error.set(null);
    obs.subscribe({
      next: (order) => {
        this.accept(order);
        this.busy.set(false);
      },
      error: (err) => {
        this.error.set(this.messageFrom(err));
        this.busy.set(false);
      },
    });
  }

  private accept(order: Order): void {
    this.order.set(order);
    this.amountDollars = order.outstanding_cents / 100;
    this.giftCardDollars = order.outstanding_cents / 100;
  }

  private messageFrom(err: unknown): string {
    const body = (
      err as { error?: { error?: { code?: string; details?: { available_cents?: number } } } }
    )?.error?.error;
    const code = body?.code;
    const map: Record<string, string> = {
      overpayment_rejected: 'That is more than is outstanding. Enter the surplus as a tip instead.',
      gift_card_not_found: 'No gift card with that code.',
      gift_card_void: 'That gift card has been voided.',
      insufficient_balance: `Not enough left on the card${
        body?.details?.available_cents !== undefined
          ? ` — $${(body.details.available_cents / 100).toFixed(2)} available`
          : ''
      }.`,
      no_membership: 'This client has no membership.',
      no_membership_credit: 'No membership credit available.',
      membership_wrong_location:
        'That membership belongs to another location and needs an override.',
      unsettled: 'Still outstanding — take the remainder before settling.',
      discount_above_manager_limit:
        'That is more than a Manager can discount on this order. Ask the Owner to apply it.',
      discount_exceeds_remaining: 'The discount is larger than what is left to pay.',
      discount_not_permitted: 'Only the Owner or a Manager can give a discount.',
      reason_required: 'Give a reason for the discount.',
      order_not_open: 'This order is already closed.',
      appointment_not_completed: 'Complete the appointment before settling.',
      appointment_not_active: 'This appointment was cancelled, so there is nothing to check out.',
      therapist_assignment_required: 'Assign the therapist on the schedule before checkout.',
      nothing_to_credit: 'Nothing is left on this order for the membership to cover.',
    };
    return code ? (map[code] ?? code) : 'Something went wrong';
  }
}
