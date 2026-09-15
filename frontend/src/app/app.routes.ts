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
    path: 'reset-password/:token',
    loadComponent: () => import('./features/auth/reset-password').then((m) => m.ResetPasswordPage),
  },
  {
    path: 'rate/:token',
    loadComponent: () => import('./features/rating/rating').then((m) => m.PublicRatingPage),
  },
  {
    path: 'dashboard',
    canActivate: [authGuard],
    loadComponent: () => import('./features/dashboard/dashboard').then((m) => m.DashboardPage),
  },
  {
    path: 'profile',
    canActivate: [authGuard],
    loadComponent: () => import('./features/profile/profile').then((m) => m.ProfilePage),
  },
  {
    path: 'notes',
    canActivate: [authGuard],
    loadComponent: () => import('./features/notes/notes').then((m) => m.Notes),
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
    path: 'staff-requests',
    canActivate: [authGuard],
    loadComponent: () =>
      import('./features/staff-requests/staff-requests').then((m) => m.StaffRequestsPage),
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
    path: 'admin/audit-log',
    canActivate: [authGuard, ownerGuard],
    loadComponent: () => import('./features/admin/audit-log/audit-log').then((m) => m.AuditLogPage),
  },
  {
    // Doc 01 §3.1 / doc 05 §6 — onboarding, qualifications and pay rates.
    path: 'admin/staff',
    canActivate: [authGuard, ownerGuard],
    loadComponent: () => import('./features/admin/staff/staff-admin').then((m) => m.StaffAdminPage),
  },
  {
    // BR-05: staff never self-edit shifts, so the roster is Manager-and-above.
    path: 'admin/roster',
    canActivate: [authGuard, bookingRoleGuard],
    loadComponent: () =>
      import('./features/admin/roster/roster-admin').then((m) => m.RosterAdminPage),
  },
  {
    // FRS §19: the menu and the price list.
    path: 'admin/services',
    canActivate: [authGuard, ownerGuard],
    loadComponent: () =>
      import('./features/admin/catalogue/catalogue-admin').then((m) => m.CatalogueAdminPage),
  },
  {
    path: 'admin/location',
    canActivate: [authGuard, ownerGuard],
    loadComponent: () =>
      import('./features/admin/location/location-admin').then((m) => m.LocationAdminPage),
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
