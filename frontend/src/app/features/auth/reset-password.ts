import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { AuthService } from '../../core/services/auth.service';
import { UiBanner, UiButton, UiField } from '../../ui';

@Component({
  selector: 'app-reset-password',
  imports: [FormsModule, UiField, UiButton, UiBanner],
  template: `
    <main class="auth">
      <form class="auth__card" (ngSubmit)="submit()">
        <h1>Choose a new password</h1>
        <ui-field label="New password"
          ><input type="password" minlength="8" [(ngModel)]="password" name="password"
        /></ui-field>
        @if (error()) {
          <ui-banner tone="error">{{ error() }}</ui-banner>
        }
        <ui-button type="submit" [full]="true">Save password</ui-button>
      </form>
    </main>
  `,
  styles: `
    .auth {
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 1rem;
    }
    .auth__card {
      display: flex;
      flex-direction: column;
      gap: 1rem;
      width: 100%;
      max-width: 24rem;
    }
  `,
})
export class ResetPasswordPage {
  private readonly auth = inject(AuthService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  protected password = '';
  protected readonly error = signal<string | null>(null);

  protected submit(): void {
    if (this.password.length < 8) {
      this.error.set('Use at least 8 characters.');
      return;
    }
    const token = this.route.snapshot.paramMap.get('token') ?? '';
    this.auth.resetPassword(token, this.password).subscribe({
      next: () => void this.router.navigate(['/sign-in']),
      error: () => this.error.set('That reset link is invalid or expired.'),
    });
  }
}
