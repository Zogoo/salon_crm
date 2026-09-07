import { Routes } from '@angular/router';

import { authGuard } from './core/guards/auth.guard';
import { bookingRoleGuard } from './core/guards/booking-role.guard';

export const routes: Routes = [
  {
    path: 'sign-in',
    loadComponent: () => import('./features/auth/sign-in').then((m) => m.SignIn),
  },
  {
    path: 'dashboard',
    canActivate: [authGuard],
    loadComponent: () => import('./features/dashboard/dashboard').then((m) => m.DashboardPage),
  },
  {
    path: 'schedule',
    canActivate: [authGuard],
    loadComponent: () => import('./features/schedule/day-board').then((m) => m.DayBoardPage),
  },
  {
    path: 'book',
    canActivate: [authGuard, bookingRoleGuard],
    loadComponent: () => import('./features/booking/booking').then((m) => m.BookingPage),
  },
  {
    path: 'clients',
    canActivate: [authGuard, bookingRoleGuard],
    loadComponent: () => import('./features/clients/clients').then((m) => m.ClientsPage),
  },
  {
    path: 'approvals',
    canActivate: [authGuard, bookingRoleGuard],
    loadComponent: () => import('./features/approvals/approvals').then((m) => m.ApprovalsPage),
  },
  { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
  { path: '**', redirectTo: 'dashboard' },
];
