import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { AuthService } from '../services/auth.service';

/** Blocks a route unless a token is present; the API is the real authority. */
export const authGuard: CanActivateFn = (_route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  if (auth.token) {
    return true;
  }

  return router.createUrlTree(['/sign-in'], { queryParams: { redirect: state.url } });
};
