import { LocationScope } from '../../shared/location-scope';
import { Component, OnInit, inject, signal } from '@angular/core';
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
    LocationScope,
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

  /** Names the location and range, so a figure is never read out of context. */
  protected subtitle(): string {
    return `Revenue, liabilities and fees at ${this.ctx.current()?.name ?? 'this location'} — kept apart on purpose, because adding them together is the most common mistake in salon accounting.`;
  }

  // Set once the location is known — the salon's day, not the browser's.
  protected from = '';
  protected to = '';

  ngOnInit(): void {
    // `?from=&to=` lets the dashboard's revenue tile open the same day here.
    const query = this.route.snapshot.queryParamMap;
    void this.ctx.load().then(() => {
      const today = todayIn(this.ctx.current()?.timezone);
      this.from = query.get('from') || today;
      this.to = query.get('to') || this.from;
      this.runAll();
    });
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    const today = todayIn(this.ctx.current()?.timezone);
    this.from = today;
    this.to = today;
    this.runAll();
  }

  protected runAll(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.error.set(null);

    this.api.dailyRevenue(loc.id, this.from, this.to).subscribe({
      next: (r) => this.revenue.set(r),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load revenue'),
    });
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
