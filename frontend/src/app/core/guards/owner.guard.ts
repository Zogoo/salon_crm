import { inject } from '@angular/core';
import { CanActivateFn, Router, UrlTree } from '@angular/router';
import { catchError, map, of } from 'rxjs';

import { AuthService } from '../services/auth.service';

/**
 * BR-02: pay rates, earnings and the money reports are the Owner's alone — a
 * Manager is the front desk and sits in a public-facing area.
 *
 * The API enforces this too (403 / omitted fields). This guard exists so a
 * Manager is never shown a screen they cannot use.
 */
export const ownerGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  const decide = (role: string | undefined): boolean | UrlTree =>
    role === 'owner' ? true : router.createUrlTree(['/dashboard']);

  const user = auth.user();
  if (user) return decide(user.role);
  if (!auth.token) return router.createUrlTree(['/sign-in']);

  // On a hard load the shell restores the session asynchronously; wait for it
  // rather than bouncing the Owner off their own reports on refresh.
  return auth.loadCurrentUser().pipe(
    map((loaded) => decide(loaded.role)),
    catchError(() => of(router.createUrlTree(['/sign-in']))),
  );
};
