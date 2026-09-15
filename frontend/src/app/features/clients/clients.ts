import { Component, OnInit, inject, signal } from '@angular/core';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { DecimalPipe } from '@angular/common';
import { forkJoin, of, Subscription } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { DestroyRef } from '@angular/core';
import { AuthService } from '../../core/services/auth.service';
import { FormsModule } from '@angular/forms';

import {
  ClientGiftCard,
  ClientHistorySummary,
  ClientOrderHistory,
  ClientRating,
  ClientRecord,
  PreferenceVersion,
} from '../../core/models';
import { MassagelabService } from '../../core/services/massagelab.service';
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
  statusTone,
} from '../../ui';

/** FRS §11 — client profiles and the preferences form (§11.1). */
@Component({
  selector: 'app-clients',
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
  templateUrl: './clients.html',
  // Shared list-and-detail layout first, then what is specific here.
  styleUrls: ['../../ui/layouts.scss', './clients.scss'],
})
export class ClientsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly auth = inject(AuthService);
  private readonly destroyRef = inject(DestroyRef);
  private detailRequest?: Subscription;
  protected readonly giftCards = signal<ClientGiftCard[]>([]);
  protected readonly ratings = signal<Record<number, ClientRating>>({});
  protected readonly orders = signal<ClientOrderHistory[]>([]);
  protected readonly preferenceVersions = signal<PreferenceVersion[]>([]);
  protected readonly historySummary = signal<ClientHistorySummary | null>(null);
  protected readonly error = signal<string | null>(null);

  protected canReadHistory(): boolean {
    return ['owner', 'manager'].includes(this.auth.user()?.role ?? '');
  }

  protected readonly clients = signal<ClientRecord[]>([]);
  protected readonly selected = signal<ClientRecord | null>(null);
  protected readonly saved = signal(false);
  protected edit = { first_name: '', last_name: '', phone: '', email: '', date_of_birth: '' };
  protected mergeTargetId: number | null = null;

  protected tone(status: string) {
    return statusTone(status);
  }
  protected humanStatus(status: string) {
    return humanise(status);
  }

  protected contact(client: ClientRecord): string {
    return [client.phone, client.email].filter(Boolean).join(' · ');
  }

  /**
   * BR-20 counters. Shown as plain counts with no judgement attached — the
   * desk decides what to do with them.
   */
  protected reliability(client: ClientRecord): Fact[] {
    return [
      { label: 'No-shows', value: client.no_show_count ?? 0 },
      { label: 'Late cancellations', value: client.late_cancel_count ?? 0 },
      { label: 'Visits recorded', value: client.appointments?.length ?? 0 },
    ];
  }
  protected search = '';
  protected pref = { attention_areas: '', avoid_areas: '', pressure: '', other_requests: '' };

  ngOnInit(): void {
    this.reload();
  }

  protected reload(): void {
    this.api.clients(this.search).subscribe(({ clients }) => this.clients.set(clients));
  }

  protected open(client: ClientRecord): void {
    this.detailRequest?.unsubscribe();
    this.saved.set(false);
    this.error.set(null);
    this.selected.set(null);
    this.giftCards.set([]);
    this.ratings.set({});
    this.orders.set([]);
    this.preferenceVersions.set([]);
    this.historySummary.set(null);
    this.detailRequest = forkJoin({
      client: this.api.client(client.id),
      ratings: this.canReadHistory() ? this.api.clientRatings(client.id) : of({ ratings: [] }),
      cards: this.canReadHistory() ? this.api.clientGiftCards(client.id) : of({ gift_cards: [] }),
      orders: this.canReadHistory() ? this.api.clientOrders(client.id) : of({ orders: [] }),
      versions: this.canReadHistory()
        ? this.api.clientPreferenceVersions(client.id)
        : of({ versions: [] }),
      summary: this.canReadHistory() ? this.api.clientHistorySummary(client.id) : of(null),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: ({ client: full, ratings, cards, orders, versions, summary }) => {
          this.selected.set(full);
          this.ratings.set(Object.fromEntries(ratings.ratings.map((r) => [r.appointment_id, r])));
          this.giftCards.set(cards.gift_cards);
          this.orders.set(orders.orders);
          this.preferenceVersions.set(versions.versions);
          this.historySummary.set(summary);
          this.edit = {
            first_name: full.first_name,
            last_name: full.last_name,
            phone: full.phone,
            email: full.email ?? '',
            date_of_birth: full.date_of_birth ?? '',
          };
          this.pref = {
            attention_areas: full.preference?.attention_areas ?? '',
            avoid_areas: full.preference?.avoid_areas ?? '',
            pressure: full.preference?.pressure ?? '',
            other_requests: full.preference?.other_requests ?? '',
          };
        },
        error: () => this.error.set('Could not load client history. Please try again.'),
      });
  }

  protected saveClient(): void {
    const client = this.selected();
    if (!client) return;
    this.api.updateClient(client.id, this.edit).subscribe({
      next: (updated) => {
        this.selected.set({ ...client, ...updated });
        this.saved.set(true);
        this.reload();
      },
      error: () => this.error.set('Could not save the client'),
    });
  }

  protected mergeClient(client: ClientRecord): void {
    if (!this.mergeTargetId || this.mergeTargetId === client.id) return;
    this.api.mergeClient(client.id, this.mergeTargetId).subscribe({
      next: (target) => {
        this.mergeTargetId = null;
        this.reload();
        this.open(target);
      },
      error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not merge the clients'),
    });
  }

  protected savePreferences(): void {
    const client = this.selected();
    if (!client) return;
    this.api.savePreferences(client.id, this.pref).subscribe((updated) => {
      this.selected.set(updated);
      this.saved.set(true);
    });
  }
}
