import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { EarningPeriod, EarningsReport, StaffMember } from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import {
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiField,
  UiPage,
  UiTable,
  humanise,
} from '../../ui';
import { todayIn } from '../../core/salon-date';

/**
 * FRS §4 and §8 — the Staff Earnings section.
 *
 * The quantity column counts sessions **as paid** (BR-33): a 60-minute massage
 * booked with a 30-minute add-on is one unit in the 90-minute row, not one in
 * each of 60 and 30.
 */
@Component({
  selector: 'app-earnings',
  imports: [FormsModule, DecimalPipe, UiPage, UiCard, UiField, UiButton, UiChip, UiEmpty, UiTable, UiBanner],
  templateUrl: './earnings.html',
  styleUrl: '../../ui/layouts.scss',
})
export class EarningsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly periods = signal<EarningPeriod[]>([]);
  protected readonly selectedPeriod = signal<EarningPeriod | null>(null);
  protected readonly staff = signal<StaffMember[]>([]);
  protected readonly report = signal<EarningsReport | null>(null);
  protected readonly error = signal<string | null>(null);

  /** The lengths pay is defined for (FRS §4). */
  protected readonly ladder = [30, 45, 60, 75, 90, 120];

  protected humanStatus(value: string) { return humanise(value); }

  protected staffId: number | null = null;
  protected from = '';
  protected to = '';

  // FRS §4: manual session and tip entry, for corrections or off-system work.
  protected manual = { duration_minutes: 60, quantity: 1, service_date: '', note: '' };

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      const salonToday = todayIn(this.ctx.current()?.timezone);
      const [f, t] = this.semiMonthly(new Date(`${salonToday}T12:00:00Z`));
      this.from = f;
      this.to = t;
      this.manual.service_date = salonToday;

      const loc = this.ctx.current();
      if (loc) this.api.staff(loc.id).subscribe(({ staff }) => this.staff.set(staff));
      this.loadPeriods();
    });
  }

  /** FRS §8: the two standing periods are 1st–15th and 16th–end of month. */
  private semiMonthly(date: Date): [string, string] {
    const y = date.getFullYear();
    const m = date.getMonth();
    const iso = (d: Date) => d.toISOString().slice(0, 10);
    return date.getDate() <= 15
      ? [iso(new Date(Date.UTC(y, m, 1))), iso(new Date(Date.UTC(y, m, 15)))]
      : [iso(new Date(Date.UTC(y, m, 16))), iso(new Date(Date.UTC(y, m + 1, 0)))];
  }

  protected loadPeriods(): void {
    this.api.earningPeriods().subscribe(({ periods }) => this.periods.set(periods));
  }

  protected openPeriod(p: EarningPeriod): void {
    this.api.periodStatements(p.id).subscribe((full) => this.selectedPeriod.set(full));
  }

  protected build(p: EarningPeriod): void {
    this.api.buildPeriod(p.id).subscribe((full) => {
      this.selectedPeriod.set(full);
      this.loadPeriods();
    });
  }

  protected lock(p: EarningPeriod): void {
    this.api.lockPeriod(p.id).subscribe((full) => {
      this.selectedPeriod.set(full);
      this.loadPeriods();
    });
  }

  protected runReport(): void {
    if (!this.staffId) return;
    this.error.set(null);
    this.api.staffEarnings(this.staffId, this.from, this.to).subscribe({
      next: (r) => this.report.set(r),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load earnings'),
    });
  }

  protected addManual(): void {
    if (!this.staffId) return;
    this.error.set(null);
    this.api
      .addEarningLine({
        staff_profile_id: this.staffId,
        service_date: this.manual.service_date,
        duration_minutes: this.manual.duration_minutes,
        quantity: this.manual.quantity,
        note: this.manual.note,
      })
      .subscribe({
        next: () => this.runReport(),
        error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not add the line'),
      });
  }
}
