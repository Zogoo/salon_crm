import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { beforeEach, describe, expect, it } from 'vitest';

import { ConfirmService } from '../../../ui';
import { StaffDetailPage } from './staff-detail';

describe('StaffDetailPage', () => {
  let page: StaffDetailPage;
  let http: HttpTestingController;
  let answer = { confirmed: true, value: '2026-09-30' };

  beforeEach(() => {
    answer = { confirmed: true, value: '2026-09-30' };
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: ConfirmService,
          useValue: { ask: async () => answer, confirm: async () => answer.confirmed },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    page = TestBed.runInInjectionContext(() => new StaffDetailPage());
  });

  // BR-35: all six rungs go together. A partial ladder is a therapist whose
  // pay fails on some bookings, so the form always submits the whole thing.
  it('always sends the complete six-rung ladder, in cents', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.member.set({ id: 3, display_name: 'Oyun' });
    p.rateForm = { 30: 25, 45: 35, 60: 45, 75: 55, 90: 65, 120: 85 };
    p.rateEffectiveFrom = '2026-07-01';
    p.saveRates();

    const req = http.expectOne((r) => r.url.endsWith('/staff/3/session_rates'));
    expect(req.request.body.rates).toHaveLength(6);
    expect(req.request.body.rates[2]).toEqual({ duration_minutes: 60, rate_cents: 4500 });
    expect(req.request.body.effective_from).toBe('2026-07-01');
  });

  it('seeds the form from the ladder in force, ignoring closed periods', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.seedRateForm([
      {
        duration_minutes: 60,
        rate_cents: 4000,
        effective_from: '2026-01-01',
        effective_to: '2026-06-30',
      },
      { duration_minutes: 60, rate_cents: 5000, effective_from: '2026-07-01', effective_to: null },
    ]);
    expect(p.rateForm[60]).toBe(50);
    expect(p.rateForm[90]).toBe(0);
  });

  it('asks before offboarding, and explains a refusal caused by booked appointments', async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.member.set({ id: 9, display_name: 'Rin', status: 'active' });
    await p.offboard();

    const req = http.expectOne((r) => r.url.endsWith('/staff/9/offboard'));
    expect(req.request.body.termination_date).toBe('2026-09-30');
    req.flush(
      { error: { code: 'offboard_blocked', details: { appointment_ids: [4, 5] } } },
      { status: 423, statusText: 'Locked' },
    );
    expect(p.error()).toContain('4, 5');
  });

  it('does nothing when the confirmation is cancelled', async () => {
    answer = { confirmed: false, value: '' };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.member.set({ id: 9, display_name: 'Rin', status: 'active' });
    await p.offboard();
    http.expectNone((r) => r.url.endsWith('/offboard'));
  });
});
