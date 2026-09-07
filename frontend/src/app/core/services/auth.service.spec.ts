import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';

import { AuthService } from './auth.service';
import { environment } from '../../../environments/environment';

describe('AuthService', () => {
  let service: AuthService;
  let http: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();

    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });

    service = TestBed.inject(AuthService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('stores the token and user on sign in', () => {
    service.signIn('demo@example.com', 'password123').subscribe();

    const req = http.expectOne(`${environment.apiUrl}/auth/sign_in`);
    expect(req.request.method).toBe('POST');

    req.flush({
      token: 'jwt-token',
      user: { id: 1, email: 'demo@example.com', name: 'Demo', avatar_url: null },
    });

    expect(service.token).toBe('jwt-token');
    expect(service.isSignedIn()).toBe(true);
    expect(service.user()?.email).toBe('demo@example.com');
  });

  it('clears the token and user on sign out', () => {
    service.signIn('demo@example.com', 'password123').subscribe();
    http.expectOne(`${environment.apiUrl}/auth/sign_in`).flush({
      token: 'jwt-token',
      user: { id: 1, email: 'demo@example.com', name: 'Demo', avatar_url: null },
    });

    service.signOut();

    expect(service.token).toBeNull();
    expect(service.isSignedIn()).toBe(false);
  });
});
