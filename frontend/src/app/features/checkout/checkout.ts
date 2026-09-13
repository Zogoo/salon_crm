import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { Order, PaymentMethod } from '../../core/models';
import { AuthService } from '../../core/services/auth.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { UiBanner, UiButton, UiCard, UiEmpty, UiField, UiPage, UiTable, humanise } from '../../ui';

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

  // FRS §21: the terminal prompts 20 / 25 / 30 or a custom amount.
  protected readonly tipPresets = [20, 25, 30];

  protected readonly outstandingDollars = computed(
    () => (this.order()?.outstanding_cents ?? 0) / 100,
  );
  protected readonly settled = computed(() => this.order()?.status === 'paid');
  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');

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

  /**
   * BR-23: a payment cannot be edited, so a mis-keyed amount is corrected by
   * voiding it and recording the right one. Owner only — the API enforces it.
   */
  protected voidPayment(paymentId: number): void {
    const order = this.order();
    if (!order) return;
    const reason = window.prompt('Why is this payment being voided?');
    if (!reason) return;
    this.run(this.api.voidPayment(order.id, paymentId, reason));
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
    };
    return code ? (map[code] ?? code) : 'Something went wrong';
  }
}
