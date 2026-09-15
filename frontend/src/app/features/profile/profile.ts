import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../core/services/auth.service';
import { UiBanner, UiButton, UiCard, UiField, UiPage } from '../../ui';

@Component({
  selector: 'app-profile',
  imports: [FormsModule, UiPage, UiCard, UiField, UiButton, UiBanner],
  templateUrl: './profile.html',
  styleUrl: '../../ui/layouts.scss',
})
export class ProfilePage {
  protected readonly auth = inject(AuthService);
  protected name = this.auth.user()?.name ?? '';
  protected avatar: File | undefined;
  protected readonly notice = signal<string | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly otpSetup = signal<{ secret: string; otpauth_url: string } | null>(null);
  protected otpCode = '';

  protected chooseAvatar(event: Event): void {
    this.avatar = (event.target as HTMLInputElement).files?.[0];
  }

  protected save(): void {
    this.auth.updateProfile(this.name, this.avatar).subscribe({
      next: () => this.notice.set('Profile saved.'),
      error: () => this.error.set('Could not save the profile.'),
    });
  }

  protected removeAvatar(): void {
    this.auth.removeAvatar().subscribe({ next: () => this.notice.set('Avatar removed.') });
  }

  protected startOtp(): void {
    this.auth.enrolOtp().subscribe({
      next: (setup) => this.otpSetup.set(setup),
      error: () => this.error.set('Could not start two-factor authentication.'),
    });
  }

  protected confirmOtp(): void {
    this.auth.confirmOtp(this.otpCode).subscribe({
      next: () => {
        this.notice.set('Two-factor authentication enabled.');
        this.otpSetup.set(null);
      },
      error: () => this.error.set('That authentication code is not valid.'),
    });
  }
}
