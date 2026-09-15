import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { Appointment } from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
import { DayBoardPage } from './day-board';

const appointment: Appointment = {
  id: 9,
  reference: 'APT-9',
  status: 'scheduled',
  starts_at: '2026-09-14T10:00:00-05:00',
  service_ends_at: '2026-09-14T11:00:00-05:00',
  ends_at: '2026-09-14T11:15:00-05:00',
  duration_minutes: 60,
  room: { id: 2, name: 'One' },
  client: { id: 3, full_name: 'Client Test', phone: '123' },
  therapists: [{ id: 4, display_name: 'Anna' }],
  total_price_cents: 8000,
  client_note: null,
};

describe('DayBoardPage appointment actions', () => {
  let page: any;
  let http: HttpTestingController;
  let router: Router;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: LocationContextService, useValue: { current: () => ({ id: 1 }) } },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    router = TestBed.inject(Router);
    page = TestBed.runInInjectionContext(() => new DayBoardPage());
  });

  it('prompts for a rating, then completes and opens checkout in one server call', () => {
    const navigate = vi.spyOn(router, 'navigate').mockResolvedValue(true);
    page.checkout(appointment);
    expect(page.checkoutPrompt()).toBe(true);
    page.ratingScore = 9;
    page.submitRatingAndCheckout(appointment);

    http.expectOne((request) => request.url.endsWith('/ratings')).flush({ id: 1 });
    http
      .expectOne((request) => request.url.endsWith('/appointments/9/complete_for_checkout'))
      .flush({ appointment: { ...appointment, status: 'completed' }, order_id: 22 });
    http.expectNone((request) => request.url.endsWith('/transition'));
    expect(navigate).toHaveBeenCalledWith(['/checkout', 9]);
  });

  it('lets a client decline to rate without blocking checkout', () => {
    const navigate = vi.spyOn(router, 'navigate').mockResolvedValue(true);
    page.checkout(appointment);
    page.declineRatingAndCheckout(appointment);

    http.expectNone((request) => request.url.endsWith('/ratings'));
    http
      .expectOne((request) => request.url.endsWith('/appointments/9/complete_for_checkout'))
      .flush({ appointment: { ...appointment, status: 'completed' }, order_id: 22 });
    expect(navigate).toHaveBeenCalledWith(['/checkout', 9]);
  });

  it('offers Cancel after check-in, and no actions on a no-show', () => {
    expect(page.nextActions('checked_in')).toContain('cancelled');
    expect(page.nextActions('no_show')).toEqual([]);
  });

  it('records a deposit against the appointment', () => {
    page.deposit = { dollars: 20, method: 'zelle', reference: 'ZL-1' };
    page.recordDeposit(appointment);

    const request = http.expectOne((candidate) =>
      candidate.url.endsWith('/appointments/9/deposit'),
    );
    expect(request.request.body).toEqual({
      amount_cents: 2000,
      method: 'zelle',
      reference: 'ZL-1',
    });
    request.flush({ ...appointment, deposit: { amount_cents: 2000, status: 'held' } });
    expect(page.depositNotice()).toContain('$20.00');
  });

  it('explains a Manager discount refusal in words', () => {
    page.discount = { dollars: 50, reason: 'Complaint' };
    page.applyDiscount(appointment);
    http.expectOne((request) => request.url.endsWith('/orders')).flush({ id: 22 });
    http
      .expectOne((request) => request.url.endsWith('/orders/22/discounts'))
      .flush(
        {
          error: { code: 'discount_above_manager_limit', message: 'discount_above_manager_limit' },
        },
        { status: 422, statusText: 'Unprocessable' },
      );
    expect(page.error()).toContain('Ask the Owner');
  });

  it('sends the chosen therapist team for a pending assignment', () => {
    page.assignmentIds = [4];
    page.assignStaff({ ...appointment, assignment_pending: true });
    const request = http.expectOne((candidate) =>
      candidate.url.endsWith('/appointments/9/assign_staff'),
    );
    expect(request.request.body.staff_profile_ids).toEqual([4]);
    request.flush({ ...appointment, assignment_pending: false });
  });

  it('opens the order and applies a discount from the calendar', () => {
    page.discount = { dollars: 12.5, reason: 'Loyal client' };
    page.applyDiscount(appointment);

    http
      .expectOne((request) => request.url.endsWith('/orders') && request.method === 'POST')
      .flush({
        id: 22,
      });
    const discount = http.expectOne(
      (request) => request.url.endsWith('/orders/22/discounts') && request.method === 'POST',
    );
    expect(discount.request.body).toEqual({ amount_cents: 1250, reason: 'Loyal client' });
    discount.flush({ id: 22 });
    expect(page.discountNotice()).toContain('$12.50');
  });
});
