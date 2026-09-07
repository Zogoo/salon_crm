import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';

import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-sign-in',
  imports: [ReactiveFormsModule, RouterLink, TranslatePipe],
  template: `
    <section class="card auth">
      <h1>{{ 'auth.sign_in' | translate }}</h1>

      <form [formGroup]="form" (ngSubmit)="submit()">
        <label>
          <span>{{ 'auth.email' | translate }}</span>
          <input type="email" formControlName="email" autocomplete="email" />
        </label>

        <label>
          <span>{{ 'auth.password' | translate }}</span>
          <input type="password" formControlName="password" autocomplete="current-password" />
        </label>

        @if (error()) {
          <p class="error">{{ error() }}</p>
        }

        <button class="primary" type="submit" [disabled]="form.invalid || loading()">
          {{ 'auth.sign_in' | translate }}
        </button>
      </form>

      <p>
        {{ 'auth.no_account' | translate }}
        <a routerLink="/sign-up">{{ 'auth.sign_up' | translate }}</a>
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
export class SignIn {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected readonly loading = signal(false);
  protected readonly error = signal('');

  protected readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
  });

  protected submit(): void {
    if (this.form.invalid) {
      return;
    }

    this.loading.set(true);
    this.error.set('');

    const { email, password } = this.form.getRawValue();
    this.auth.signIn(email, password).subscribe({
      next: () => {
        const redirect = this.route.snapshot.queryParamMap.get('redirect') ?? '/dashboard';
        void this.router.navigateByUrl(redirect);
      },
      error: (err) => {
        this.loading.set(false);
        this.error.set(err?.error?.error ?? 'Sign in failed');
      },
    });
  }
}
