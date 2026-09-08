import { Routes } from '@angular/router';

import { authGuard } from './core/guards/auth.guard';
import { bookingRoleGuard } from './core/guards/booking-role.guard';
import { ownerGuard } from './core/guards/owner.guard';

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
  {
    path: 'checkout/:appointmentId',
    canActivate: [authGuard, bookingRoleGuard],
    loadComponent: () => import('./features/checkout/checkout').then((m) => m.CheckoutPage),
  },
  {
    path: 'gift-cards',
    canActivate: [authGuard, bookingRoleGuard],
    loadComponent: () => import('./features/giftcards/giftcards').then((m) => m.GiftCardsPage),
  },
  {
    path: 'membership',
    canActivate: [authGuard, bookingRoleGuard],
    loadComponent: () => import('./features/membership/membership').then((m) => m.MembershipPage),
  },
  {
    // BR-02: earnings and money reports are Owner-only.
    path: 'earnings',
    canActivate: [authGuard, ownerGuard],
    loadComponent: () => import('./features/earnings/earnings').then((m) => m.EarningsPage),
  },
  {
    path: 'reports',
    canActivate: [authGuard, ownerGuard],
    loadComponent: () => import('./features/reports/reports').then((m) => m.ReportsPage),
  },
  {
    // The in-location touchscreen. Staff-authenticated but deliberately bare.
    path: 'kiosk',
    canActivate: [authGuard],
    loadComponent: () => import('./features/kiosk/kiosk').then((m) => m.KioskPage),
  },
  { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
  { path: '**', redirectTo: 'dashboard' },
];
