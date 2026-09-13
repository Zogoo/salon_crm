import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { AuthService } from '../../core/services/auth.service';
import { UiBanner, UiButton, UiField } from '../../ui';

@Component({
  selector: 'app-sign-in',
  imports: [ReactiveFormsModule, UiField, UiButton, UiBanner],
  template: `
    <main class="auth">
      <form class="auth__card" [formGroup]="form" (ngSubmit)="submit()">
        <h1 class="auth__title">Massagelab</h1>
        <p class="auth__sub">Sign in to the front-desk console.</p>

        <ui-field label="Email">
          <input type="email" formControlName="email" autocomplete="email" data-testid="email" />
        </ui-field>

        <ui-field label="Password">
          <input
            type="password"
            formControlName="password"
            autocomplete="current-password"
            data-testid="password"
          />
        </ui-field>

        @if (otpNeeded()) {
          <ui-field
            label="Authentication code"
            hint="The 6-digit code from your authenticator app."
          >
            <input
              formControlName="otpCode"
              inputmode="numeric"
              autocomplete="one-time-code"
              data-testid="otp"
            />
          </ui-field>
        }

        @if (error()) {
          <ui-banner tone="error">{{ error() }}</ui-banner>
        }

        <ui-button type="submit" [full]="true" [disabled]="form.invalid || loading()">
          {{ loading() ? 'Signing in…' : 'Sign in' }}
        </ui-button>
      </form>
    </main>
  `,
  styles: `
    @use '../../../styles/tokens' as *;

    .auth {
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: var(--sp-4);
      background: var(--md-surface-container-low);
    }
    .auth__card {
      display: flex;
      flex-direction: column;
      gap: var(--sp-4);
      width: 100%;
      max-width: 24rem;
      padding: var(--sp-6) var(--sp-5);
      background: var(--md-surface-container-lowest);
      border-radius: var(--md-shape-lg);
      box-shadow: var(--md-elev-1);
    }
    .auth__title {
      @include type-headline-sm;
    }
    .auth__sub {
      @include type-body-md;
      color: var(--md-on-surface-variant);
      margin-bottom: var(--sp-2);
    }
  `,
})
export class SignIn {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected readonly loading = signal(false);
  protected readonly error = signal('');
  /** Only asked for once the password is right, so it is never a puzzle. */
  protected readonly otpNeeded = signal(false);

  protected readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
    otpCode: [''],
  });

  protected submit(): void {
    if (this.form.invalid) return;

    this.loading.set(true);
    this.error.set('');

    const { email, password, otpCode } = this.form.getRawValue();
    this.auth.signIn(email, password, otpCode || undefined).subscribe({
      next: () => {
        const redirect = this.route.snapshot.queryParamMap.get('redirect') ?? '/dashboard';
        void this.router.navigateByUrl(redirect);
      },
      error: (err) => {
        this.loading.set(false);
        const code = err?.error?.error?.code;
        if (code === 'otp_required') {
          this.otpNeeded.set(true);
          this.error.set('Enter the code from your authenticator app to finish signing in.');
        } else if (code === 'otp_invalid') {
          this.otpNeeded.set(true);
          this.error.set(
            'That code was not right. Codes change every 30 seconds — try the current one.',
          );
        } else {
          this.error.set('That email and password did not match an account.');
        }
      },
    });
  }
}
