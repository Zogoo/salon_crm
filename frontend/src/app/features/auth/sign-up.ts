import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';

import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-sign-up',
  imports: [ReactiveFormsModule, RouterLink, TranslatePipe],
  template: `
    <section class="card auth">
      <h1>{{ 'auth.sign_up' | translate }}</h1>

      <form [formGroup]="form" (ngSubmit)="submit()">
        <label>
          <span>{{ 'auth.name' | translate }}</span>
          <input type="text" formControlName="name" autocomplete="name" />
        </label>

        <label>
          <span>{{ 'auth.email' | translate }}</span>
          <input type="email" formControlName="email" autocomplete="email" />
        </label>

        <label>
          <span>{{ 'auth.password' | translate }}</span>
          <input type="password" formControlName="password" autocomplete="new-password" />
        </label>

        <label>
          <span>{{ 'auth.password_confirmation' | translate }}</span>
          <input
            type="password"
            formControlName="password_confirmation"
            autocomplete="new-password"
          />
        </label>

        @if (error()) {
          <p class="error">{{ error() }}</p>
        }

        <button class="primary" type="submit" [disabled]="form.invalid || loading()">
          {{ 'auth.sign_up' | translate }}
        </button>
      </form>

      <p>
        {{ 'auth.have_account' | translate }}
        <a routerLink="/sign-in">{{ 'auth.sign_in' | translate }}</a>
      </p>
    </section>
  `,
  styles: `
    .auth {
      max-width: 24rem;
      margin: 0 auto;
    }
  `,
})
export class SignUp {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly loading = signal(false);
  protected readonly error = signal('');

  protected readonly form = this.fb.nonNullable.group({
    name: ['', [Validators.required]],
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(8)]],
    password_confirmation: ['', [Validators.required]],
  });

  protected submit(): void {
    if (this.form.invalid) {
      return;
    }

    this.loading.set(true);
    this.error.set('');

    this.auth.signUp(this.form.getRawValue()).subscribe({
      next: () => void this.router.navigate(['/dashboard']),
      error: (err) => {
        this.loading.set(false);
        const message = err?.error?.error;
        this.error.set(Array.isArray(message) ? message.join(', ') : (message ?? 'Sign up failed'));
      },
    });
  }
}
