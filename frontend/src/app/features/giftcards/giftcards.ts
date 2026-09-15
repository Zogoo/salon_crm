import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription, finalize } from 'rxjs';
import { FormsModule } from '@angular/forms';

import { ListState } from '../../core/list-state';
import { ClientRecord, GiftCard, PageMeta, PaymentMethod } from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { ClientPicker } from '../../shared/client-picker';
import {
  ConfirmService,
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
  UiPaginator,
  UiSheet,
  humanise,
} from '../../ui';

type Mode = 'lookup' | 'sell';
type CardFilters = { status: string; location_id: string };

const EMPTY_FORM = () => ({
  amountDollars: 100,
  code: '',
  buyer_client_id: null as number | null,
  payment_method: 'card' as PaymentMethod,
  buyer_name: '',
  buyer_phone: '',
  recipient_name: '',
});

/**
 * FRS §12, §13 — find a card among hundreds (by code, buyer or recipient),
 * read its history, and sell new ones. Looking up and selling are separate
 * tabs, because they are separate jobs at the desk.
 */
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
    UiFacts,
    UiBanner,
    UiIcon,
    UiPaginator,
    UiSheet,
    ClientPicker,
  ],
  templateUrl: './giftcards.html',
  styleUrls: ['../../ui/layouts.scss', '../../ui/data-table.scss', './giftcards.scss'],
})
export class GiftCardsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly auth = inject(AuthService);
  private readonly confirm = inject(ConfirmService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  protected readonly ctx = inject(LocationContextService);

  /** Looking a card up is the everyday task, so it is where the page opens. */
  protected readonly mode = signal<Mode>('lookup');
  protected readonly rows = signal<GiftCard[]>([]);
  protected readonly meta = signal<PageMeta | null>(null);
  protected readonly loading = signal(true);
  protected readonly selected = signal<GiftCard | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly issued = signal<GiftCard | null>(null);
  protected readonly issuing = signal(false);
  protected readonly linkedBuyer = signal<ClientRecord | null>(null);
  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');
  protected readonly skeleton = Array.from({ length: 6 });

  protected readonly methods: PaymentMethod[] = ['card', 'cash', 'zelle', 'online', 'other'];
  protected readonly amountPresets = [50, 100, 150, 200];
  protected form = EMPTY_FORM();
  private request?: Subscription;

  protected readonly list = new ListState<CardFilters>(
    this.router,
    this.route,
    { sort: 'sold', dir: 'desc', filters: { status: '', location_id: '' } },
    () => this.reload(),
  );

  protected readonly summary = computed(() => {
    const f = this.list.filters();
    const parts: string[] = [];
    if (f.status) parts.push(this.statusFilterLabel(f.status));
    if (f.location_id) {
      parts.push(
        `sold at ${this.ctx.locations().find((l) => String(l.id) === f.location_id)?.name ?? 'one location'}`,
      );
    }
    if (this.list.q().trim()) parts.push(`matching “${this.list.q().trim()}”`);
    return parts.join(' · ');
  });

  protected humanStatus = humanise;

  ngOnInit(): void {
    if (this.route.snapshot.queryParamMap.get('mode') === 'sell') this.mode.set('sell');
    this.list.readFromUrl();
    void this.ctx.load().then(() => this.reload());
  }

  protected setMode(mode: Mode): void {
    this.mode.set(mode);
    this.error.set(null);
    this.notice.set(null);
    // Kept in the address, so Back and a bookmark return to the same task.
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParamsHandling: 'merge',
      queryParams: { mode: mode === 'sell' ? 'sell' : null },
      replaceUrl: true,
    });
  }

  protected statusFilterLabel(status: string): string {
    return (
      {
        active: 'active',
        expired: 'expired with money left',
        depleted: 'used up',
        void: 'void',
      }[status] ?? status
    );
  }

  protected statusChip(card: GiftCard): {
    label: string;
    tone: 'success' | 'warning' | 'neutral' | 'error';
  } {
    if (card.status === 'void') return { label: 'Void', tone: 'error' };
    if (card.status === 'depleted') return { label: 'Used up', tone: 'neutral' };
    if (card.expired) return { label: 'Expired', tone: 'warning' };
    return { label: 'Active', tone: 'success' };
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
    this.request?.unsubscribe();
    this.loading.set(true);
    this.request = this.api.giftCardList(this.list.query()).subscribe({
      next: ({ gift_cards, meta }) => {
        this.rows.set(gift_cards);
        this.meta.set(meta ?? null);
        this.loading.set(false);
        // A scanned or linked code that matches exactly one card opens it straight away.
        const q = this.list.q().trim().toUpperCase();
        if (q && gift_cards.length === 1 && gift_cards[0].code === q && !this.selected()) {
          this.open(gift_cards[0]);
        }
      },
      error: () => {
        this.error.set('Could not load gift cards. Check the connection and try again.');
        this.loading.set(false);
      },
    });
  }

  protected open(card: GiftCard): void {
    this.api.giftCard(card.code).subscribe({
      next: (full) => this.selected.set(full),
      error: () => this.error.set('Could not open that card.'),
    });
  }

  // --- selling ----------------------------------------------------------

  protected linkBuyer(client: ClientRecord | null): void {
    this.linkedBuyer.set(client);
    this.form.buyer_client_id = client?.id ?? null;
    this.form.buyer_name = client?.full_name ?? '';
    this.form.buyer_phone = client?.phone ?? '';
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
    this.linkedBuyer.set(null);
  }

  // --- Owner corrections ------------------------------------------------

  protected async adjust(card: GiftCard): Promise<void> {
    const { confirmed, values } = await this.confirm.ask({
      title: `Correct the balance of ${card.code}`,
      message: `Currently $${(card.current_balance_cents / 100).toFixed(2)}. The correction is added to the history and the audit log with your name.`,
      confirmLabel: 'Apply correction',
      fields: [
        {
          key: 'amount',
          label: 'Change in dollars',
          required: true,
          placeholder: 'e.g. 25 or -10',
          hint: 'Use a minus sign to take money off the card.',
        },
        { key: 'reason', label: 'Reason', required: true },
      ],
    });
    if (!confirmed) return;
    const cents = Math.round(Number(values['amount']) * 100);
    if (!Number.isFinite(cents) || cents === 0) {
      this.error.set('Enter an amount other than zero, like 25 or -10.');
      return;
    }
    this.api.adjustGiftCard(card.id, cents, values['reason']).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.notice.set('Balance corrected.');
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

  protected async voidCard(card: GiftCard): Promise<void> {
    const ok = await this.confirm.confirm({
      title: `Void gift card ${card.code}?`,
      message: `The $${(card.current_balance_cents / 100).toFixed(2)} left on it can no longer be spent at any location. The card and its history stay on record.`,
      confirmLabel: 'Void card',
      tone: 'danger',
    });
    if (!ok) return;
    this.api.voidGiftCard(card.id).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.notice.set(`${card.code} is void.`);
        this.reload();
      },
      error: () => this.error.set('Could not void the card.'),
    });
  }
}
