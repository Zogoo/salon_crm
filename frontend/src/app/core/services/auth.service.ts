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

  private accept(res: AuthResponse): void {
    localStorage.setItem(TOKEN_KEY, res.token);
    this.currentUser.set(res.user);
  }
}
