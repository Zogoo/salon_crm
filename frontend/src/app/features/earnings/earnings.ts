import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import {
  EarningLine,
  EarningPeriod,
  EarningStatement,
  EarningsReport,
  ManagerPayoutReport,
  StaffMember,
} from '../../core/models';
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
import { StaffPicker } from '../../shared/staff-picker';

/**
 * FRS §4 and §8 — the Staff Earnings section.
 *
 * The quantity column counts sessions **as paid** (BR-33): a 60-minute massage
 * booked with a 30-minute add-on is one unit in the 90-minute row, not one in
 * each of 60 and 30.
 */
@Component({
  selector: 'app-earnings',
  imports: [
    StaffPicker,
    FormsModule,
    DecimalPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiTable,
    UiBanner,
  ],
  templateUrl: './earnings.html',
  styleUrl: '../../ui/layouts.scss',
})
export class EarningsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly periods = signal<EarningPeriod[]>([]);
  protected readonly selectedPeriod = signal<EarningPeriod | null>(null);
  protected readonly selectedStatement = signal<EarningStatement | null>(null);
  protected readonly staff = signal<StaffMember[]>([]);
  protected readonly report = signal<EarningsReport | null>(null);
  protected readonly lines = signal<EarningLine[]>([]);
  protected readonly managerPayouts = signal<ManagerPayoutReport | null>(null);
  protected readonly error = signal<string | null>(null);

  /** The lengths pay is defined for (FRS §4). */
  protected readonly ladder = [30, 45, 60, 75, 90, 120];

  protected humanStatus(value: string) {
    return humanise(value);
  }

  protected staffId: number | null = null;
  protected from = '';
  protected to = '';

  // FRS §4: manual session and tip entry, for corrections or off-system work.
  // A length makes the line count as a session in the quantity table (FRS §4,
  // §8); a correction or off-system payment is an amount only.
  protected manual: {
    duration_minutes: number | null;
    dollars: number;
    service_date: string;
    note: string;
  } = {
    duration_minutes: null,
    dollars: 0,
    service_date: '',
    note: '',
  };
  protected lineAmounts: Record<number, number> = {};
  protected lineNotes: Record<number, string> = {};
  protected adjustment = { service_date: '', dollars: 0, reason: '' };

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      const salonToday = todayIn(this.ctx.current()?.timezone);
      const [f, t] = this.semiMonthly(new Date(`${salonToday}T12:00:00Z`));
      this.from = f;
      this.to = t;
      this.manual.service_date = salonToday;
      this.adjustment.service_date = salonToday;
      this.loadPeriods();
      this.loadManagerPayouts();
    });
  }

  private loadManagerPayouts(): void {
    const month = this.from.slice(0, 7);
    if (!month) return;
    this.api.managerPayouts(month).subscribe({
      next: (report) => this.managerPayouts.set(report),
      error: () => this.managerPayouts.set(null),
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

  protected openStatement(statement: EarningStatement): void {
    this.api
      .earningStatement(statement.id)
      .subscribe((detail) => this.selectedStatement.set(detail));
  }

  protected addAdjustment(statement: EarningStatement): void {
    if (!this.adjustment.reason.trim()) return;
    this.api
      .adjustEarningStatement(
        statement.id,
        this.adjustment.service_date,
        Math.round(this.adjustment.dollars * 100),
        this.adjustment.reason.trim(),
      )
      .subscribe({
        next: (updated) => {
          this.selectedStatement.set(updated);
          this.adjustment = { ...this.adjustment, dollars: 0, reason: '' };
          const period = this.selectedPeriod();
          if (period) this.openPeriod(period);
        },
        error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not add adjustment'),
      });
  }

  protected statementPdf(statement: EarningStatement): void {
    this.api.earningStatementPdf(statement.id).subscribe((blob) => {
      const url = URL.createObjectURL(blob);
      window.open(url, '_blank', 'noopener');
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    });
  }

  protected runReport(): void {
    if (!this.staffId) return;
    this.error.set(null);
    this.api.staffEarnings(this.staffId, this.from, this.to).subscribe({
      next: (r) => {
        this.report.set(r);
        this.loadLines();
      },
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load earnings'),
    });
  }

  /** "2026-09" reads as "September 2026". */
  protected monthLabel(month: string): string {
    const [year, m] = month.split('-').map(Number);
    if (!year || !m) return month;
    return new Date(Date.UTC(year, m - 1, 1)).toLocaleDateString('en-US', {
      month: 'long',
      year: 'numeric',
      timeZone: 'UTC',
    });
  }

  protected addManual(): void {
    if (!this.staffId) return;
    this.error.set(null);
    this.api
      .addEarningLine({
        staff_profile_id: this.staffId,
        service_date: this.manual.service_date,
        duration_minutes: this.manual.duration_minutes ?? undefined,
        quantity: 1,
        amount_cents: Math.round(this.manual.dollars * 100),
        note: this.manual.note,
      })
      .subscribe({
        next: () => this.runReport(),
        error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not add the line'),
      });
  }

  protected saveLine(line: EarningLine): void {
    this.api
      .updateEarningLine(
        line.id,
        Math.round((this.lineAmounts[line.id] ?? 0) * 100),
        this.lineNotes[line.id] ?? '',
      )
      .subscribe({
        next: () => this.runReport(),
        error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not update the line'),
      });
  }

  private loadLines(): void {
    if (!this.staffId) return;
    this.api.earningLines(this.staffId, this.from, this.to).subscribe(({ lines }) => {
      this.lines.set(lines);
      for (const line of lines) {
        this.lineAmounts[line.id] = line.amount_cents / 100;
        this.lineNotes[line.id] = line.note ?? '';
      }
    });
  }
}
