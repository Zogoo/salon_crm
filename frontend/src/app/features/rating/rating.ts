import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';

import { MassagelabService } from '../../core/services/massagelab.service';
import { UiBanner, UiButton, UiCard, UiField } from '../../ui';

@Component({
  selector: 'app-public-rating',
  imports: [FormsModule, UiCard, UiField, UiButton, UiBanner],
  template: `
    <main class="rating">
      <ui-card heading="How was your massage?" [sub]="visit()?.location ?? ''">
        @if (done() || visit()?.already_rated) {
          <ui-banner tone="success">Thank you. Your feedback has been recorded.</ui-banner>
        } @else if (visit()) {
          <p>
            Choose a score from 1 to 10 for your visit with
            {{ visit()?.therapist || 'your therapist' }}.
          </p>
          <div class="scores">
            @for (value of scores; track value) {
              <button type="button" [class.on]="score === value" (click)="score = value">
                {{ value }}
              </button>
            }
          </div>
          <ui-field label="What went well?" [optional]="true">
            <textarea rows="3" [(ngModel)]="feedback"></textarea>
          </ui-field>
          <ui-field label="What could improve?" [optional]="true">
            <textarea rows="3" [(ngModel)]="improvement"></textarea>
          </ui-field>
          <label
            ><input type="checkbox" [(ngModel)]="wouldRecommend" /> I would recommend
            Massagelab</label
          >
          <ui-button icon="send" [disabled]="!score" (click)="submit()">Send feedback</ui-button>
        }
        @if (error()) {
          <ui-banner tone="error">{{ error() }}</ui-banner>
        }
      </ui-card>
    </main>
  `,
  styles: `
    .rating {
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 1rem;
    }
    .rating ui-card {
      width: min(36rem, 100%);
    }
    .scores {
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 0.5rem;
      margin: 1rem 0;
    }
    .scores button {
      min-height: 3rem;
      border: 1px solid #777;
      border-radius: 0.5rem;
      background: white;
    }
    .scores button.on {
      background: #006a6a;
      color: white;
    }
  `,
})
export class PublicRatingPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly route = inject(ActivatedRoute);
  protected readonly visit = signal<{
    location: string;
    therapist: string | null;
    already_rated: boolean;
  } | null>(null);
  protected readonly done = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly scores = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  protected score: number | null = null;
  protected feedback = '';
  protected improvement = '';
  protected wouldRecommend = true;

  ngOnInit(): void {
    this.api.publicRating(this.token).subscribe({
      next: (visit) => this.visit.set(visit),
      error: () => this.error.set('This feedback link is invalid or expired.'),
    });
  }

  protected submit(): void {
    if (!this.score) return;
    this.api
      .submitPublicRating(this.token, {
        score: this.score,
        feedback: this.feedback,
        improvement: this.improvement,
        would_recommend: this.wouldRecommend,
      })
      .subscribe({
        next: () => this.done.set(true),
        error: () => this.error.set('Could not save your feedback.'),
      });
  }

  private get token(): string {
    return this.route.snapshot.paramMap.get('token') ?? '';
  }
}
