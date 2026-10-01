import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';

import {
  ClientLogRow,
  DailyRevenue,
  GiftCardLiability,
  MembershipReport,
  NoShowReport,
  RatingAlertsReport,
  RatingsReport,
  RetentionReport,
  UtilizationReport,
} from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';
import { UiBanner, UiButton, UiCard, UiEmpty, UiField, UiPage, UiTable, humanise } from '../../ui';

type Period = 'day' | 'week' | 'month' | 'custom';

/**
 * FRS §9, §10, §12.
 *
 * BR-48 is the rule this screen exists to make visible: service revenue, gift
 * card and membership liabilities, and no-show fees are three different things.
 * They are shown apart on purpose — adding them together is the most common
 * accounting error in salon software.
 */
@Component({
  selector: 'app-reports',
  imports: [
    FormsModule,
    DecimalPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiTable,
    UiBanner,
    UiEmpty,
  ],
  templateUrl: './reports.html',
  // Shared list-and-detail layout first, then what is specific here.
  styleUrls: ['../../ui/layouts.scss', './reports.scss'],
})
export class ReportsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);
  private readonly route = inject(ActivatedRoute);

  protected readonly revenue = signal<DailyRevenue | null>(null);
  protected readonly log = signal<ClientLogRow[] | null>(null);
  protected readonly liability = signal<GiftCardLiability | null>(null);
  protected readonly fees = signal<{
    total_cents: number;
    orders: Record<string, unknown>[];
  } | null>(null);
  protected readonly noShows = signal<NoShowReport | null>(null);
  protected readonly utilization = signal<UtilizationReport | null>(null);
  protected readonly therapistPreview = 8;
  protected readonly showAllTherapists = signal(false);

  /** Busiest first; the full team only on request. */
  protected therapistRows(u: UtilizationReport): UtilizationReport['therapists'] {
    const sorted = [...u.therapists].sort((a, b) => b.utilization_percent - a.utilization_percent);
    return this.showAllTherapists() ? sorted : sorted.slice(0, this.therapistPreview);
  }
  protected readonly retention = signal<RetentionReport | null>(null);
  protected readonly ratings = signal<RatingsReport | null>(null);
  protected readonly ratingAlerts = signal<RatingAlertsReport | null>(null);
  protected readonly membership = signal<MembershipReport | null>(null);
  protected readonly error = signal<string | null>(null);

  /** Names what the figures cover, so a figure is never read out of context. */
  protected subtitle(): string {
    return 'Revenue with tips and transaction fees, and — kept apart — the liabilities and fees that are not revenue.';
  }

  /** Addendum §3: the same report by day, week, month or any range. */
  protected readonly periods: { key: Period; label: string }[] = [
    { key: 'day', label: 'Day' },
    { key: 'week', label: 'Week' },
    { key: 'month', label: 'Month' },
    { key: 'custom', label: 'Custom' },
  ];
  protected readonly period = signal<Period>('day');
  /** One location's id, or "all" for the whole business (Owner). */
  protected readonly scope = signal<string>('');
  /** The day the week or month is taken around. */
  protected anchor = '';

  // Set once the location is known — the salon's day, not the browser's.
  protected from = '';
  protected to = '';
  private readonly ran = signal({ from: '', to: '' });

  protected readonly scopeName = computed(() =>
    this.scope() === 'all'
      ? 'All locations'
      : (this.ctx.locations().find((l) => String(l.id) === this.scope())?.name ?? ''),
  );

  protected readonly rangeLabel = computed(() => {
    const { from, to } = this.ran();
    if (!from) return '';
    const fmt = (d: string, opts: Intl.DateTimeFormatOptions) =>
      new Date(`${d}T12:00:00`).toLocaleDateString('en-US', opts);
    const full: Intl.DateTimeFormatOptions = {
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    };
    const start: Intl.DateTimeFormatOptions = { weekday: 'short', day: 'numeric', month: 'short' };
    return from === to ? fmt(from, full) : `${fmt(from, start)} – ${fmt(to, full)}`;
  });

  ngOnInit(): void {
    // `?from=&to=` lets the dashboard's revenue tile open the same day here.
    const query = this.route.snapshot.queryParamMap;
    void this.ctx.load().then(() => {
      this.scope.set(String(this.ctx.current()?.id ?? ''));
      const today = todayIn(this.ctx.current()?.timezone);
      this.from = query.get('from') || today;
      this.to = query.get('to') || this.from;
      this.anchor = this.from;
      if (this.from !== this.to) this.period.set('custom');
      this.runAll();
    });
  }

  protected setScope(value: string): void {
    this.scope.set(value);
    // Choosing one location makes it the one every other screen shows too.
    if (value !== 'all') this.ctx.select(Number(value));
    this.runAll();
  }

  protected setPeriod(period: Period): void {
    this.period.set(period);
    if (period !== 'custom') this.applyPeriod();
  }

  /** Day, the Monday-to-Sunday week, or the calendar month around the anchor. */
  protected applyPeriod(): void {
    const d = new Date(`${this.anchor || todayIn(this.ctx.current()?.timezone ?? null)}T12:00:00Z`);
    const iso = (x: Date) => x.toISOString().slice(0, 10);
    if (this.period() === 'day') {
      this.from = this.to = iso(d);
    } else if (this.period() === 'week') {
      const monday = new Date(d);
      monday.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
      const sunday = new Date(monday);
      sunday.setUTCDate(monday.getUTCDate() + 6);
      this.from = iso(monday);
      this.to = iso(sunday);
    } else if (this.period() === 'month') {
      this.from = iso(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1)));
      this.to = iso(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)));
    }
    this.runAll();
  }

  protected runAll(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.error.set(null);
    this.ran.set({ from: this.from, to: this.to });

    const all = this.scope() === 'all';
    this.api
      .dailyRevenue(all ? this.ctx.locations().map((l) => l.id) : loc.id, this.from, this.to)
      .subscribe({
        next: (r) => this.revenue.set(r),
        error: (err) => this.error.set(err?.error?.error ?? 'Could not load revenue'),
      });
    if (all) {
      // The other reports are per location; the banner says so.
      this.log.set(null);
      this.liability.set(null);
      this.fees.set(null);
      this.noShows.set(null);
      this.utilization.set(null);
      this.retention.set(null);
      this.ratings.set(null);
      this.ratingAlerts.set(null);
      this.membership.set(null);
      return;
    }
    this.api.clientLog(loc.id, this.from).subscribe({
      next: ({ rows }) => this.log.set(rows),
      error: () => this.log.set([]),
    });
    this.api.giftCardLiability(loc.id).subscribe({
      next: (l) => this.liability.set(l),
      error: () => this.liability.set(null),
    });
    this.api.outstandingFees(loc.id).subscribe({
      next: (f) => this.fees.set(f),
      error: () => this.fees.set(null),
    });
    this.api.noShows(loc.id, this.from, this.to).subscribe({
      next: (r) => this.noShows.set(r),
      error: () => this.noShows.set(null),
    });
    this.api.utilization(loc.id, this.from, this.to).subscribe({
      next: (r) => this.utilization.set(r),
      error: () => this.utilization.set(null),
    });
    this.api.clientRetention(loc.id, this.from, this.to).subscribe({
      next: (r) => this.retention.set(r),
      error: () => this.retention.set(null),
    });
    this.api.ratingsReport(loc.id, this.from, this.to).subscribe({
      next: (report) => this.ratings.set(report),
      error: () => this.ratings.set(null),
    });
    this.api.ratingAlerts(loc.id, this.from, this.to).subscribe({
      next: (report) => this.ratingAlerts.set(report),
      error: () => this.ratingAlerts.set(null),
    });
    this.api.membershipReport(loc.id, this.from, this.to).subscribe({
      next: (report) => this.membership.set(report),
      error: () => this.membership.set(null),
    });
  }

  protected humanStatus(value: string): string {
    return humanise(value);
  }

  protected methodKeys(r: DailyRevenue): string[] {
    return Object.keys(r.by_method);
  }

  protected locationKeys(l: GiftCardLiability): string[] {
    return Object.keys(l.by_location);
  }

  protected entries(map: Record<string, number>): { key: string; value: number }[] {
    return Object.keys(map).map((key) => ({ key, value: map[key] }));
  }
}
