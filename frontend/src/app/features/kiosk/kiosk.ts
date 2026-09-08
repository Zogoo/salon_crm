import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';

interface Waiting {
  id: number;
  reference: string;
  client_name: string;
  therapist: string;
  time: string;
}

/**
 * FRS §11.2 — the in-location touchscreen.
 *
 * Deliberately its own screen with big targets and nothing else on it: it sits
 * unattended in a public room, so a walk-up must not be able to reach the rest
 * of the console from here.
 */
@Component({
  selector: 'app-kiosk',
  imports: [FormsModule],
  templateUrl: './kiosk.html',
  styleUrl: './kiosk.scss',
})
export class KioskPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly queue = signal<Waiting[]>([]);
  protected readonly chosen = signal<Waiting | null>(null);
  protected readonly done = signal(false);
  protected readonly error = signal<string | null>(null);

  protected readonly scores = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  protected score: number | null = null;
  protected feedback = '';
  protected improvement = '';
  protected wouldRecommend: boolean | null = null;

  ngOnInit(): void {
    void this.ctx.load().then(() => this.reload());
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.kioskQueue(loc.id).subscribe({
      next: ({ appointments }) => this.queue.set(appointments),
      error: (err) => this.error.set(err?.error?.error ?? 'Could not load the queue'),
    });
  }

  protected choose(w: Waiting): void {
    this.chosen.set(w);
    this.reset();
  }

  protected submit(): void {
    const appt = this.chosen();
    if (!appt || this.score === null) return;
    this.error.set(null);

    this.api
      .submitRating({
        appointment_id: appt.id,
        score: this.score,
        feedback: this.feedback || null,
        improvement: this.improvement || null,
        would_recommend: this.wouldRecommend,
      })
      .subscribe({
        next: () => {
          this.done.set(true);
          this.reload();
          // Return to the queue on its own, so the screen is ready for the
          // next person without anyone tapping it.
          setTimeout(() => {
            this.done.set(false);
            this.chosen.set(null);
          }, 4000);
        },
        error: (err) => this.error.set(err?.error?.error?.code ?? 'Could not save your rating'),
      });
  }

  protected back(): void {
    this.chosen.set(null);
    this.reset();
  }

  private reset(): void {
    this.score = null;
    this.feedback = '';
    this.improvement = '';
    this.wouldRecommend = null;
    this.done.set(false);
  }
}
