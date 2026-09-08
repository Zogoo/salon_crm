import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { Appointment, CareNote, DayBoard, Room } from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';

interface Placed {
  appointment: Appointment;
  leftPct: number;
  widthPct: number;
  bufferPct: number;
}

/** FRS §6 — rooms as rows, time across, 09:00–22:00. */
@Component({
  selector: 'app-day-board',
  imports: [FormsModule, RouterLink, DecimalPipe, WallClockPipe],
  templateUrl: './day-board.html',
  styleUrl: './day-board.scss',
})
export class DayBoardPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  protected readonly ctx = inject(LocationContextService);
  protected readonly auth = inject(AuthService);

  protected readonly board = signal<DayBoard | null>(null);
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly selected = signal<Appointment | null>(null);
  protected readonly careNotes = signal<CareNote[]>([]);
  protected newCareNote = '';
  protected date = '';

  protected readonly hours = computed(() => {
    const b = this.board();
    if (!b) return [];
    const open = Number(b.opens_at.slice(0, 2));
    const close = Number(b.closes_at.slice(0, 2));
    return Array.from({ length: close - open + 1 }, (_, i) => open + i);
  });

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.date ||= todayIn(this.ctx.current()?.timezone);
      this.reload();
    });
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.loading.set(true);
    this.error.set(null);
    this.api.dayBoard(loc.id, this.date).subscribe({
      next: (board) => {
        this.board.set(board);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.error ?? 'Could not load the schedule');
        this.loading.set(false);
      },
    });
  }

  protected onLocationChange(id: string): void {
    this.ctx.select(Number(id));
    this.selected.set(null);
    this.reload();
  }

  protected shiftDay(days: number): void {
    const d = new Date(this.date);
    d.setDate(d.getDate() + days);
    this.date = d.toISOString().slice(0, 10);
    this.reload();
  }

  /** Positions an appointment as a percentage of the open day. */
  protected placed(room: Room): Placed[] {
    const b = this.board();
    if (!b) return [];
    const open = this.toMinutes(b.opens_at);
    const close = this.toMinutes(b.closes_at);
    const span = close - open;

    return b.appointments
      .filter((a) => a.room.id === room.id)
      .map((a) => {
        const start = this.minutesOfDay(a.starts_at);
        const serviceEnd = this.minutesOfDay(a.service_ends_at);
        const end = this.minutesOfDay(a.ends_at);
        return {
          appointment: a,
          leftPct: ((start - open) / span) * 100,
          widthPct: ((serviceEnd - start) / span) * 100,
          // The 15-minute buffer is real reserved time, so it is drawn.
          bufferPct: ((end - serviceEnd) / span) * 100,
        };
      });
  }

  protected select(appointment: Appointment): void {
    this.newCareNote = '';
    this.careNotes.set([]);
    this.api.appointment(appointment.id).subscribe({
      next: (full) => this.selected.set(full),
      error: () => this.selected.set(appointment),
    });
    // Every read is audit-logged server-side — it is the only way to answer
    // "who looked at this" (doc 04 §5).
    this.api.careNotes(appointment.id).subscribe({
      next: ({ care_notes }) => this.careNotes.set(care_notes),
      error: () => this.careNotes.set([]),
    });
  }

  /** BR-44: append-only. A correction is a new note, never an edit. */
  protected addCareNote(appointment: Appointment): void {
    const body = this.newCareNote.trim();
    if (!body) return;
    this.api.addCareNote(appointment.id, body).subscribe({
      next: (note) => {
        this.careNotes.set([...this.careNotes(), note]);
        this.newCareNote = '';
      },
      error: (err) =>
        this.error.set(
          err?.error?.error?.code === 'not_assigned_to_this_appointment'
            ? 'Only a therapist on this appointment can write its care note.'
            : 'Could not save the note',
        ),
    });
  }

  protected checkout(appointment: Appointment): void {
    void this.router.navigate(['/checkout', appointment.id]);
  }

  protected transition(appointment: Appointment, to: string): void {
    this.api.transition(appointment.id, to).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.reload();
      },
      error: (err) => this.error.set(err?.error?.error ?? 'That change is not allowed'),
    });
  }

  protected nextActions(status: string): string[] {
    return (
      {
        pending_approval: ['cancelled'],
        scheduled: ['checked_in', 'cancelled', 'no_show'],
        checked_in: ['in_progress', 'no_show'],
        in_progress: ['completed'],
      }[status] ?? []
    );
  }

  protected label(action: string): string {
    return (
      {
        checked_in: 'Check in',
        in_progress: 'Start',
        completed: 'Complete',
        cancelled: 'Cancel',
        no_show: 'No-show',
      }[action] ?? action
    );
  }

  protected newBooking(): void {
    void this.router.navigate(['/book'], { queryParams: { date: this.date } });
  }

  private toMinutes(hhmm: string): number {
    const [h, m] = hhmm.split(':').map(Number);
    return h * 60 + m;
  }

  /** Minutes since midnight in the *salon's* wall clock — see WallClockPipe. */
  private minutesOfDay(iso: string): number {
    const m = /T(\d{2}):(\d{2})/.exec(iso);
    return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
  }
}
