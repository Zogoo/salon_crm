import { Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';
import { finalize, Subscription } from 'rxjs';
import { FormsModule } from '@angular/forms';

import { ClientRecord, GiftCard, PaymentMethod } from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import {
  Fact,
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiFacts,
  UiField,
  UiIcon,
  UiPage,
  UiTable,
  humanise,
  statusTone,
} from '../../ui';

type Mode = 'lookup' | 'sell';

const EMPTY_FORM = () => ({
  amountDollars: 100,
  code: '',
  buyer_client_id: null as number | null,
  payment_method: 'card' as PaymentMethod,
  buyer_name: '',
  buyer_phone: '',
  recipient_name: '',
});

/** FRS §12, §13 — look up a card (barcode or code), read its history, and sell new ones. */
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
    UiIcon,
  ],
  templateUrl: './giftcards.html',
  // Shared list-and-detail layout first, then what is specific here.
  styleUrls: ['../../ui/layouts.scss', './giftcards.scss'],
})
export class GiftCardsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly auth = inject(AuthService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private buyerRequest?: Subscription;
  protected readonly ctx = inject(LocationContextService);

  /** Looking a card up is the everyday task, so it is where the page opens. */
  protected readonly mode = signal<Mode>('lookup');
  protected readonly cards = signal<GiftCard[]>([]);
  protected readonly selected = signal<GiftCard | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly issued = signal<GiftCard | null>(null);
  protected readonly issuing = signal(false);
  protected readonly buyers = signal<ClientRecord[]>([]);
  protected readonly searchingBuyers = signal(false);
  protected readonly linkedBuyer = signal<ClientRecord | null>(null);
  protected readonly confirmingVoid = signal(false);
  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');

  protected readonly methods: PaymentMethod[] = ['card', 'cash', 'zelle', 'online', 'other'];
  protected readonly amountPresets = [50, 100, 150, 200];
  protected form = EMPTY_FORM();
  protected buyerSearch = '';
  protected search = '';
  protected adjustment = { dollars: 0, reason: '' };

  protected humanStatus(value: string) {
    return humanise(value);
  }
  protected statusTone(value: string) {
    return statusTone(value);
  }

  ngOnInit(): void {
    if (this.route.snapshot.queryParamMap.get('mode') === 'sell') this.mode.set('sell');
    void this.ctx.load().then(() => this.reload());
  }

  protected setMode(mode: Mode): void {
    this.mode.set(mode);
    this.error.set(null);
    // Kept in the address, so Back and a bookmark return to the same task.
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { mode: mode === 'sell' ? 'sell' : null },
      replaceUrl: true,
    });
  }

  protected cardFacts(card: GiftCard): Fact[] {
    const money = (c: number) => `$${(c / 100).toFixed(2)}`;
    return [
      { label: 'Balance', value: money(card.current_balance_cents) },
      { label: 'Face value', value: money(card.initial_value_cents) },
      { label: 'Bought by', value: card.buyer?.name || 'Not recorded' },
      ...(card.recipient?.name ? [{ label: 'For', value: card.recipient.name }] : []),
      { label: 'Sold at', value: card.sold_at_location?.name },
      { label: 'Sold', value: card.sold_at?.slice(0, 10) },
      {
        label: 'Expires',
        value: card.expires_at?.slice(0, 10),
        hint: 'Flags the card; never forfeits the balance.',
      },
    ];
  }

  protected reload(): void {
    this.api.giftCards(this.search).subscribe({
      next: ({ gift_cards }) => this.cards.set(gift_cards),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load gift cards'),
    });
  }

  protected open(card: GiftCard): void {
    this.confirmingVoid.set(false);
    this.api.giftCard(card.code).subscribe((full) => this.selected.set(full));
  }

  // --- selling ----------------------------------------------------------

  protected searchBuyers(): void {
    this.buyerRequest?.unsubscribe();
    this.buyers.set([]);
    const term = this.buyerSearch.trim();
    if (term.length < 2) return;
    this.searchingBuyers.set(true);
    this.buyerRequest = this.api
      .clients(term)
      .pipe(
        takeUntilDestroyed(this.destroyRef),
        finalize(() => this.searchingBuyers.set(false)),
      )
      .subscribe({
        next: ({ clients }) => this.buyers.set(clients),
        error: () => this.error.set('Could not search clients. Please try again.'),
      });
  }

  protected linkBuyer(client: ClientRecord): void {
    this.linkedBuyer.set(client);
    this.form.buyer_client_id = client.id;
    this.form.buyer_name = client.full_name;
    this.form.buyer_phone = client.phone ?? '';
    this.buyers.set([]);
    this.buyerSearch = '';
  }

  protected unlinkBuyer(): void {
    this.linkedBuyer.set(null);
    this.form.buyer_client_id = null;
    this.form.buyer_name = '';
    this.form.buyer_phone = '';
  }

  protected issue(): void {
    const loc = this.ctx.current();
    if (!loc || this.issuing()) return;
    const cents = Math.round((this.form.amountDollars || 0) * 100);
    if (cents <= 0) {
      this.error.set('Enter the amount the client is paying.');
      return;
    }
    this.error.set(null);
    this.issuing.set(true);
    this.api
      .issueGiftCard({
        location_id: loc.id,
        code: this.form.code.trim(),
        buyer_client_id: this.form.buyer_client_id,
        amount_cents: cents,
        payment_method: this.form.payment_method,
        buyer_name: this.form.buyer_name.trim(),
        buyer_phone: this.form.buyer_phone.trim(),
        recipient_name: this.form.recipient_name.trim(),
      })
      .pipe(finalize(() => this.issuing.set(false)))
      .subscribe({
        next: (card) => {
          this.issued.set(card);
          this.reload();
        },
        error: (err) => {
          const error = err?.error?.error;
          this.error.set(
            error?.code === 'code_taken'
              ? 'That gift card code is already in use. Enter a different code, or leave it blank to generate one.'
              : Array.isArray(error)
                ? error.join('. ')
                : (error?.message ?? error?.code ?? 'Could not issue the card.'),
          );
        },
      });
  }

  protected viewCard(card: GiftCard): void {
    this.sellAnother();
    this.setMode('lookup');
    this.open(card);
  }

  protected sellAnother(): void {
    this.issued.set(null);
    this.form = EMPTY_FORM();
    this.unlinkBuyer();
    this.buyerSearch = '';
    this.buyers.set([]);
  }

  // --- Owner corrections ------------------------------------------------

  protected adjust(card: GiftCard): void {
    const cents = Math.round(this.adjustment.dollars * 100);
    if (!cents || !this.adjustment.reason.trim()) {
      this.error.set('Enter an amount and a reason for the correction.');
      return;
    }
    this.api.adjustGiftCard(card.id, cents, this.adjustment.reason.trim()).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.adjustment = { dollars: 0, reason: '' };
        this.reload();
      },
      error: (err) =>
        this.error.set(
          err?.error?.error?.code === 'negative_balance'
            ? 'That would take the balance below zero.'
            : 'Could not adjust the card.',
        ),
    });
  }

  /** Voiding cannot be undone, so it takes a second, deliberate press. */
  protected voidCard(card: GiftCard): void {
    if (!this.confirmingVoid()) {
      this.confirmingVoid.set(true);
      return;
    }
    this.api.voidGiftCard(card.id).subscribe({
      next: (updated) => {
        this.confirmingVoid.set(false);
        this.selected.set(updated);
        this.reload();
      },
      error: () => this.error.set('Could not void the card.'),
    });
  }
}
