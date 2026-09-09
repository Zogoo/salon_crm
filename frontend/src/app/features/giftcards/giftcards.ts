import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { GiftCard, PaymentMethod } from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import {
  Fact,
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiFacts,
  UiField,
  UiPage,
  UiTable,
  humanise,
} from '../../ui';

/** FRS §12, §13 — sell, look up (barcode or code), and read the ledger. */
@Component({
  selector: 'app-giftcards',
  imports: [
    FormsModule,
    DecimalPipe,
    WallClockPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiTable,
    UiFacts,
    UiBanner,
  ],
  templateUrl: './giftcards.html',
  // Shared list-and-detail layout first, then what is specific here.
  styleUrls: ['../../ui/layouts.scss', './giftcards.scss'],
})
export class GiftCardsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly cards = signal<GiftCard[]>([]);
  protected readonly selected = signal<GiftCard | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly issued = signal<GiftCard | null>(null);

  protected search = '';

  protected humanStatus(value: string) { return humanise(value); }

  protected cardFacts(card: GiftCard): Fact[] {
    const money = (c: number) => `$${(c / 100).toFixed(2)}`;
    return [
      { label: 'Balance', value: money(card.current_balance_cents) },
      { label: 'Face value', value: money(card.initial_value_cents) },
      { label: 'Sold at', value: card.sold_at_location?.name },
      { label: 'Sold', value: card.sold_at?.slice(0, 10) },
      { label: 'Expires', value: card.expires_at?.slice(0, 10), hint: 'Flags the card; never forfeits the balance.' },
    ];
  }
  protected readonly methods: PaymentMethod[] = ['card', 'cash', 'zelle', 'online', 'other'];
  protected form = {
    amountDollars: 100,
    payment_method: 'card' as PaymentMethod,
    buyer_name: '',
    buyer_phone: '',
    recipient_name: '',
  };

  ngOnInit(): void {
    void this.ctx.load().then(() => this.reload());
  }

  protected reload(): void {
    this.api.giftCards(this.search).subscribe({
      next: ({ gift_cards }) => this.cards.set(gift_cards),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load gift cards'),
    });
  }

  protected open(card: GiftCard): void {
    this.api.giftCard(card.code).subscribe((full) => this.selected.set(full));
  }

  protected issue(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.error.set(null);
    this.api
      .issueGiftCard({
        location_id: loc.id,
        amount_cents: Math.round(this.form.amountDollars * 100),
        payment_method: this.form.payment_method,
        buyer_name: this.form.buyer_name,
        buyer_phone: this.form.buyer_phone,
        recipient_name: this.form.recipient_name,
      })
      .subscribe({
        next: (card) => {
          this.issued.set(card);
          this.selected.set(card);
          this.reload();
        },
        error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not issue the card'),
      });
  }
}
