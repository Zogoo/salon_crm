import { inject } from '@angular/core';
import { CanActivateFn, Router, UrlTree } from '@angular/router';
import { catchError, map, of } from 'rxjs';

import { AuthService } from '../services/auth.service';

/**
 * BR-14: only Owner and Manager reach the booking, client and approval screens.
 * The API enforces this too (403) — this guard exists so Staff are never shown
 * a screen they cannot use, not as the security boundary.
 */
export const bookingRoleGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  const decide = (role: string | undefined): boolean | UrlTree =>
    role === 'owner' || role === 'manager' ? true : router.createUrlTree(['/schedule']);

  const user = auth.user();
  if (user) return decide(user.role);
  if (!auth.token) return router.createUrlTree(['/sign-in']);

  // On a hard page load the shell restores the session asynchronously, so the
  // role is not known yet. Wait for it — assuming the worst here would bounce a
  // Manager to the schedule every time they refreshed on /book.
  return auth.loadCurrentUser().pipe(
    map((loaded) => decide(loaded.role)),
    catchError(() => of(router.createUrlTree(['/sign-in']))),
  );
};
