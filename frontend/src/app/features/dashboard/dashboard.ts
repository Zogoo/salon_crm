import { LocationScope } from '../../shared/location-scope';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { Appointment, Dashboard, DayBoard, ShiftBoard } from '../../core/models';
import { AuthService } from '../../core/services/auth.service';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';
import {
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiField,
  UiIcon,
  UiPage,
  UiStat,
  humanise,
  statusTone,
} from '../../ui';

/** A dashboard summarises; the full list is always one tap away. */
const PREVIEW = 5;
const STILL_TO_HAPPEN = ['pending_approval', 'scheduled', 'checked_in', 'in_progress'];

/**
 * FRS §15 — today at the selected location.
 *
 * Every number and every short list here answers "what needs me?" and then
 * hands over to the screen that owns the detail (schedule, roster, approvals,
 * reports), already filtered to the day being looked at. Nothing is listed in
 * full: 200 names on a dashboard is a directory, not a glance.
 */
@Component({
  selector: 'app-dashboard',
  imports: [
    FormsModule,
    DecimalPipe,
    RouterLink,
    WallClockPipe,
    UiPage,
    LocationScope,
    UiCard,
    UiChip,
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
  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');

  protected readonly data = signal<Dashboard | null>(null);
  protected readonly shifts = signal<ShiftBoard | null>(null);
  protected readonly board = signal<DayBoard | null>(null);
  protected readonly error = signal<string | null>(null);
  /** The day on screen, as a signal so the summaries follow it. */
  protected readonly day = signal('');
  protected date = '';

  protected readonly isToday = computed(
    () => this.day() === todayIn(this.ctx.current()?.timezone ?? null),
  );

  /** Names the location so the numbers are never read against the wrong one. */
  protected readonly subtitle = computed(() =>
    this.isStaff()
      ? `Your day at ${this.ctx.current()?.name ?? 'your location'}.`
      : `${this.isToday() ? 'How today is going' : 'The day'} at ${this.ctx.current()?.name ?? 'this location'}.`,
  );

  /** Today: what is still to come. Another day: everything booked. */
  protected readonly upcoming = computed(() => {
    const now = Date.now();
    const list = (this.board()?.appointments ?? [])
      .filter((a) => STILL_TO_HAPPEN.includes(a.status))
      .filter((a) => !this.isToday() || new Date(a.ends_at).getTime() > now)
      .sort((a, b) => a.starts_at.localeCompare(b.starts_at));
    return {
      items: list.slice(0, PREVIEW),
      more: Math.max(list.length - PREVIEW, 0),
      total: list.length,
    };
  });

  /** Booked with no preference and still without a therapist — checkout is blocked until assigned. */
  protected readonly unassigned = computed(
    () =>
      (this.board()?.appointments ?? []).filter(
        (a) => a.assignment_pending && STILL_TO_HAPPEN.includes(a.status),
      ).length,
  );

  protected readonly team = computed(() => {
    const working = [...(this.shifts()?.working ?? [])].sort((a, b) =>
      a.starts_at.localeCompare(b.starts_at),
    );
    return {
      items: working.slice(0, PREVIEW),
      more: Math.max(working.length - PREVIEW, 0),
      total: working.length,
      off: this.shifts()?.not_working.length ?? 0,
    };
  });

  protected readonly tone = statusTone;
  protected readonly humanStatus = humanise;

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.date ||= todayIn(this.ctx.current()?.timezone);
      this.reload();
    });
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc || !this.date) return;
    this.error.set(null);
    this.day.set(this.date);

    if (!this.isStaff()) {
      this.api.dashboard(loc.id, this.date).subscribe({
        next: (d) => this.data.set(d),
        error: () =>
          this.error.set('Could not load the dashboard. Check the connection and try again.'),
      });
    }
    // For a therapist the API returns only their own appointments.
    this.api.dayBoard(loc.id, this.date).subscribe({
      next: (b) => this.board.set(b),
      error: () => this.board.set(null),
    });
    this.api.shifts(loc.id, this.date).subscribe({
      next: (s) => this.shifts.set(s),
      error: () => this.shifts.set(null),
    });
  }

  protected shiftDay(days: number): void {
    const d = new Date(`${this.date}T12:00:00`);
    d.setDate(d.getDate() + days);
    this.date = d.toISOString().slice(0, 10);
    this.reload();
  }

  protected goToday(): void {
    this.date = todayIn(this.ctx.current()?.timezone ?? null);
    this.reload();
  }

  /** "Single 1 · Pema", or the thing the desk has to do about it. */
  protected detail(a: Appointment): string {
    const who = a.assignment_pending
      ? 'Therapist not assigned'
      : a.therapists.map((t) => t.display_name).join(' & ') || 'Unassigned';
    return `${a.room.name} · ${who}`;
  }

  protected clock(iso: string): string {
    return iso.slice(11, 16);
  }

  protected plural(n: number, one: string, many = `${one}s`): string {
    return `${n} ${n === 1 ? one : many}`;
  }

  protected openSchedule(): void {
    void this.router.navigate(['/schedule'], { queryParams: { date: this.date } });
  }
}
