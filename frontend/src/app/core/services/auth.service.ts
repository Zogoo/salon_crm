import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthResponse, User } from '../models';

const TOKEN_KEY = 'massagelab_token';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);

  private readonly currentUser = signal<User | null>(null);

  readonly user = this.currentUser.asReadonly();
  readonly isSignedIn = computed(() => this.currentUser() !== null);

  get token(): string | null {
    return localStorage.getItem(TOKEN_KEY);
  }

  // `otpCode` is only sent once the API has asked for it (doc 05 §3).
  signIn(email: string, password: string, otpCode?: string): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${environment.apiUrl}/auth/sign_in`, {
        email,
        password,
        otp_code: otpCode,
      })
      .pipe(tap((res) => this.accept(res)));
  }

  signUp(payload: {
    name: string;
    email: string;
    password: string;
    password_confirmation: string;
  }): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${environment.apiUrl}/auth/sign_up`, payload)
      .pipe(tap((res) => this.accept(res)));
  }

  /** Restores the session on boot when a token is already stored. */
  loadCurrentUser(): Observable<User> {
    return this.http
      .get<User>(`${environment.apiUrl}/auth/me`)
      .pipe(tap((user) => this.currentUser.set(user)));
  }

  signOut(): void {
    localStorage.removeItem(TOKEN_KEY);
    this.currentUser.set(null);
  }

  updateProfile(name: string, avatar?: File): Observable<User> {
    const body = new FormData();
    body.append('name', name);
    if (avatar) body.append('avatar', avatar);
    return this.http
      .patch<User>(`${environment.apiUrl}/profile`, body)
      .pipe(tap((user) => this.currentUser.set(user)));
  }

  removeAvatar(): Observable<User> {
    return this.http
      .delete<User>(`${environment.apiUrl}/profile/avatar`)
      .pipe(tap((user) => this.currentUser.set(user)));
  }

  enrolOtp(): Observable<{ secret: string; otpauth_url: string }> {
    return this.http.post<{ secret: string; otpauth_url: string }>(
      `${environment.apiUrl}/me/otp`,
      {},
    );
  }

  confirmOtp(otpCode: string): Observable<{ otp_enabled: boolean }> {
    return this.http
      .post<{ otp_enabled: boolean }>(`${environment.apiUrl}/me/otp/confirm`, {
        otp_code: otpCode,
      })
      .pipe(
        tap(() => {
          const current = this.currentUser();
          if (current) this.currentUser.set({ ...current, otp_enabled: true });
        }),
      );
  }

  requestPasswordReset(email: string): Observable<void> {
    return this.http.post<void>(`${environment.apiUrl}/password_resets`, { email });
  }

  resetPassword(token: string, password: string): Observable<void> {
    return this.http.put<void>(
      `${environment.apiUrl}/password_resets/${encodeURIComponent(token)}`,
      {
        password,
      },
    );
  }

  private accept(res: AuthResponse): void {
    localStorage.setItem(TOKEN_KEY, res.token);
    this.currentUser.set(res.user);
  }
}
