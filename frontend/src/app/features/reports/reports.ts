import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { ClientLogRow, DailyRevenue, GiftCardLiability } from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';

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
  imports: [FormsModule, DecimalPipe],
  templateUrl: './reports.html',
  styleUrl: './reports.scss',
})
export class ReportsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly revenue = signal<DailyRevenue | null>(null);
  protected readonly log = signal<ClientLogRow[] | null>(null);
  protected readonly liability = signal<GiftCardLiability | null>(null);
  protected readonly fees = signal<{ total_cents: number; orders: Record<string, unknown>[] } | null>(null);
  protected readonly error = signal<string | null>(null);

  // Set once the location is known — the salon's day, not the browser's.
  protected from = '';
  protected to = '';

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      const today = todayIn(this.ctx.current()?.timezone);
      this.from = today;
      this.to = today;
      this.runAll();
    });
  }

  protected onLocationChange(id: string): void {
    this.ctx.select(Number(id));
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
  }

  protected methodKeys(r: DailyRevenue): string[] {
    return Object.keys(r.by_method);
  }

  protected locationKeys(l: GiftCardLiability): string[] {
    return Object.keys(l.by_location);
  }
}
