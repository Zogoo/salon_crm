import { formatPhone } from '../../core/phone';
import { Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe, Location as BrowserLocation } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  ClientGiftCard,
  ClientHistorySummary,
  ClientOrderHistory,
  ClientRating,
  ClientRecord,
  ClientVisit,
  PageMeta,
  PreferenceVersion,
} from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { ClientPicker } from '../../shared/client-picker';
import {
  ConfirmService,
  Fact,
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiDialog,
  UiEmpty,
  UiFacts,
  UiField,
  UiIcon,
  UiPage,
  UiPaginator,
  humanise,
  statusTone,
} from '../../ui';

type Tab = 'visits' | 'preferences' | 'orders' | 'gift_cards';

/**
 * One client, company-wide (BR-42). Everything you can do to the record sits in
 * one action bar at the top; everything you can read is a tab below it, each
 * paged so a client with years of history loads as fast as a new one.
 */
@Component({
  selector: 'app-client-detail',
  imports: [
    FormsModule,
    RouterLink,
    DecimalPipe,
    WallClockPipe,
    UiPage,
    UiCard,
    UiButton,
    UiIcon,
    UiChip,
    UiEmpty,
    UiFacts,
    UiField,
    UiBanner,
    UiDialog,
    UiPaginator,
    ClientPicker,
  ],
  templateUrl: './client-detail.html',
  styleUrls: ['../../ui/layouts.scss', '../../ui/data-table.scss', './clients.scss'],
})
export class ClientDetailPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly browser = inject(BrowserLocation);
  private readonly confirm = inject(ConfirmService);
  private readonly destroyRef = inject(DestroyRef);
  protected readonly auth = inject(AuthService);

  protected readonly client = signal<ClientRecord | null>(null);
  protected readonly summary = signal<ClientHistorySummary | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly tab = signal<Tab>('visits');

  protected readonly visits = signal<ClientVisit[]>([]);
  protected readonly visitsMeta = signal<PageMeta | null>(null);
  protected readonly ratings = signal<Record<number, ClientRating>>({});
  protected readonly orders = signal<ClientOrderHistory[]>([]);
  protected readonly ordersMeta = signal<PageMeta | null>(null);
  protected readonly giftCards = signal<ClientGiftCard[]>([]);
  protected readonly versions = signal<PreferenceVersion[]>([]);

  protected readonly editing = signal(false);
  protected readonly merging = signal(false);
  protected readonly mergeTarget = signal<ClientRecord | null>(null);
  protected edit = { first_name: '', last_name: '', phone: '', email: '', date_of_birth: '' };
  protected pref = { attention_areas: '', avoid_areas: '', pressure: '', other_requests: '' };

  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');
  protected readonly canReadMoney = computed(() =>
    ['owner', 'manager'].includes(this.auth.user()?.role ?? ''),
  );

  private id = 0;

  protected humanStatus = humanise;
  protected tone = statusTone;

  ngOnInit(): void {
    this.route.paramMap.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((params) => {
      this.id = Number(params.get('id'));
      const tab = this.route.snapshot.queryParamMap.get('tab') as Tab | null;
      this.tab.set(
        tab && ['visits', 'preferences', 'orders', 'gift_cards'].includes(tab) ? tab : 'visits',
      );
      this.loadClient();
      this.loadTab();
    });
  }

  protected contact(c: ClientRecord): string {
    return [formatPhone(c.phone), c.email].filter(Boolean).join(' · ');
  }

  protected facts(c: ClientRecord): Fact[] {
    const s = this.summary();
    const facts: Fact[] = [
      { label: 'Visits', value: s?.visits ?? '—' },
      {
        label: 'Last visit',
        value: s?.last_visit ? s.last_visit.slice(0, 10) : 'Never',
        hint: s?.days_since_last_visit != null ? `${s.days_since_last_visit} days ago` : undefined,
      },
      { label: 'No-shows', value: c.no_show_count ?? 0 },
      { label: 'Late cancellations', value: c.late_cancel_count ?? 0 },
    ];
    if (this.canReadMoney() && s) {
      facts.push(
        { label: 'Lifetime spend', value: `$${(s.lifetime_spend_cents / 100).toFixed(2)}` },
        { label: 'Usual service', value: s.favourite_service || '—' },
        { label: 'Usual therapist', value: s.favourite_therapist || '—' },
      );
    }
    return facts;
  }

  protected selectTab(tab: Tab): void {
    this.tab.set(tab);
    void this.router.navigate([], {
      relativeTo: this.route,
      replaceUrl: true,
      queryParams: { tab: tab === 'visits' ? null : tab },
    });
    this.loadTab();
  }

  protected back(): void {
    // Back returns to the list with its search, filters and page intact.
    if (window.history.length > 1) this.browser.back();
    else void this.router.navigate(['/clients']);
  }

  protected book(): void {
    void this.router.navigate(['/book'], { queryParams: { client_id: this.id } });
  }

  // --- tabs ---------------------------------------------------------------

  protected loadVisits(page = 1): void {
    this.api.clientVisits(this.id, { page, limit: 10 }).subscribe({
      next: ({ appointments, meta }) => {
        this.visits.set(appointments);
        this.visitsMeta.set(meta);
      },
      error: () => this.error.set('Could not load the visit history.'),
    });
  }

  protected loadOrders(page = 1): void {
    this.api.clientOrderPage(this.id, { page, limit: 10 }).subscribe({
      next: ({ orders, meta }) => {
        this.orders.set(orders);
        this.ordersMeta.set(meta);
      },
      error: () => this.error.set('Could not load the orders.'),
    });
  }

  private loadTab(): void {
    switch (this.tab()) {
      case 'visits':
        this.loadVisits();
        if (this.canReadMoney()) {
          this.api.clientRatings(this.id).subscribe({
            next: ({ ratings }) =>
              this.ratings.set(Object.fromEntries(ratings.map((r) => [r.appointment_id, r]))),
          });
        }
        break;
      case 'orders':
        this.loadOrders();
        break;
      case 'gift_cards':
        this.api.clientGiftCards(this.id).subscribe({
          next: ({ gift_cards }) => this.giftCards.set(gift_cards),
          error: () => this.error.set('Could not load gift cards.'),
        });
        break;
      case 'preferences':
        this.api.clientPreferenceVersions(this.id).subscribe({
          next: ({ versions }) => this.versions.set(versions),
          error: () => this.versions.set([]),
        });
        break;
    }
  }

  private loadClient(): void {
    this.error.set(null);
    this.api.client(this.id).subscribe({
      next: (c) => {
        this.client.set(c);
        this.pref = {
          attention_areas: c.preference?.attention_areas ?? '',
          avoid_areas: c.preference?.avoid_areas ?? '',
          pressure: c.preference?.pressure ?? '',
          other_requests: c.preference?.other_requests ?? '',
        };
      },
      error: () => this.error.set('That client could not be found.'),
    });
    if (this.canReadMoney()) {
      this.api.clientHistorySummary(this.id).subscribe({
        next: (s) => this.summary.set(s),
        error: () => this.summary.set(null),
      });
    }
  }

  // --- actions ------------------------------------------------------------

  protected openEdit(): void {
    const c = this.client();
    if (!c) return;
    this.edit = {
      first_name: c.first_name,
      last_name: c.last_name,
      phone: c.phone,
      email: c.email ?? '',
      date_of_birth: c.date_of_birth ?? '',
    };
    this.editing.set(true);
  }

  protected saveEdit(): void {
    this.api.updateClient(this.id, this.edit).subscribe({
      next: (updated) => {
        this.client.update((c) => (c ? { ...c, ...updated } : updated));
        this.editing.set(false);
        this.notice.set('Contact details saved.');
      },
      error: (err) => {
        const body = err?.error?.error;
        this.error.set(Array.isArray(body) ? body.join('. ') : 'Could not save the client.');
      },
    });
  }

  protected savePreferences(): void {
    this.api.savePreferences(this.id, this.pref).subscribe({
      next: (updated) => {
        this.client.set(updated);
        this.notice.set('Preferences saved. The previous version is kept below.');
        this.api.clientPreferenceVersions(this.id).subscribe({
          next: ({ versions }) => this.versions.set(versions),
        });
      },
      error: () => this.error.set('Could not save the preferences.'),
    });
  }

  protected openMerge(event: Event): void {
    (event.target as HTMLElement).closest('details')?.removeAttribute('open');
    this.mergeTarget.set(null);
    this.merging.set(true);
  }

  /** BR-42: merging cannot be undone, so it is spelled out and confirmed. */
  protected async merge(): Promise<void> {
    const source = this.client();
    const target = this.mergeTarget();
    if (!source || !target) return;
    const ok = await this.confirm.confirm({
      title: `Merge ${source.full_name} into ${target.full_name}?`,
      message: `Every visit, order, gift card and preference moves to ${target.full_name} (${target.phone}). ${source.full_name} is marked as merged and disappears from the directory. This cannot be undone.`,
      confirmLabel: 'Merge clients',
      tone: 'danger',
    });
    if (!ok) return;
    this.api.mergeClient(source.id, target.id).subscribe({
      next: (merged) => {
        this.merging.set(false);
        void this.router.navigate(['/clients', merged.id]);
        this.notice.set(`${source.full_name} was merged into this record.`);
      },
      error: (err) =>
        this.error.set(
          err?.error?.error?.code === 'cannot_merge_into_self'
            ? 'Choose a different client to merge into.'
            : 'Could not merge the clients.',
        ),
    });
  }
}
