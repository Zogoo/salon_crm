import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { Dashboard, ShiftBoard } from '../../core/models';
import { AuthService } from '../../core/services/auth.service';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';

/** FRS §15 — today at the selected location. */
@Component({
  selector: 'app-dashboard',
  imports: [FormsModule, RouterLink, DecimalPipe],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss',
})
export class DashboardPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);
  protected readonly auth = inject(AuthService);

  protected readonly data = signal<Dashboard | null>(null);
  protected readonly shifts = signal<ShiftBoard | null>(null);
  protected readonly error = signal<string | null>(null);
  protected date = '';

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.date ||= todayIn(this.ctx.current()?.timezone);
      this.reload();
    });
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.error.set(null);
    this.api.dashboard(loc.id, this.date).subscribe({
      next: (d) => this.data.set(d),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load the dashboard'),
    });
    this.api.shifts(loc.id, this.date).subscribe({
      next: (s) => this.shifts.set(s),
      error: () => this.shifts.set(null),
    });
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    this.reload();
  }
}
