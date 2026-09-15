import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { Dashboard, ShiftBoard } from '../../core/models';
import { AuthService } from '../../core/services/auth.service';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';
import { UiBanner, UiButton, UiCard, UiEmpty, UiField, UiIcon, UiPage, UiStat } from '../../ui';

/** FRS §15 — today at the selected location. */
@Component({
  selector: 'app-dashboard',
  imports: [
    FormsModule,
    DecimalPipe,
    RouterLink,
    WallClockPipe,
    UiPage,
    UiCard,
    UiStat,
    UiBanner,
    UiEmpty,
    UiField,
    UiButton,
    UiIcon,
  ],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss',
})
export class DashboardPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  protected readonly ctx = inject(LocationContextService);
  private readonly auth = inject(AuthService);

  /** A therapist's day is their own shift, not the salon's occupancy. */
  protected readonly isStaff = computed(() => this.auth.user()?.role === 'staff');

  protected readonly data = signal<Dashboard | null>(null);
  protected readonly shifts = signal<ShiftBoard | null>(null);
  protected readonly error = signal<string | null>(null);
  protected date = '';

  /** Names the location so the numbers are never read against the wrong one. */
  protected readonly subtitle = computed(() =>
    this.isStaff()
      ? `Your day at ${this.ctx.current()?.name ?? 'your location'}.`
      : `How today is going at ${this.ctx.current()?.name ?? 'this location'}.`,
  );

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
      error: () =>
        this.error.set('Could not load the dashboard. Check the connection and try again.'),
    });
    this.api.shifts(loc.id, this.date).subscribe({
      next: (s) => this.shifts.set(s),
      error: () => this.shifts.set(null),
    });
  }

  protected openSchedule(): void {
    void this.router.navigate(['/schedule']);
  }
}
