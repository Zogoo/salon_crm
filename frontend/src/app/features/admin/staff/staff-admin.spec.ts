import { HttpClient, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { describe, expect, it, beforeEach } from 'vitest';

import { StaffAdminPage } from './staff-admin';

describe('StaffAdminPage', () => {
  let page: StaffAdminPage;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()],
    });
    TestBed.inject(HttpClient);
    http = TestBed.inject(HttpTestingController);
    page = TestBed.runInInjectionContext(() => new StaffAdminPage());
  });

  function selectLocation(p: { ctx: { load: () => Promise<void> } }) {
    void p.ctx.load();
    http
      .expectOne((r) => r.url.endsWith('/locations'))
      .flush({ locations: [{ id: 7, name: 'Luma', timezone: 'America/Chicago' }] });
  }

  // BR-35: all six rungs go together. A partial ladder is a therapist whose
  // pay fails on some bookings, so the form always submits the whole thing.
  it('always sends the complete six-rung ladder, in cents', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    selectLocation(p);
    p.selected.set({ id: 3, display_name: 'Oyun' });
    p.rateForm = { 30: 25, 45: 35, 60: 45, 75: 55, 90: 65, 120: 85 };
    p.rateEffectiveFrom = '2026-07-01';
    p.saveRates();

    const req = http.expectOne((r) => r.url.endsWith('/staff/3/session_rates'));
    expect(req.request.body.rates).toHaveLength(6);
    expect(req.request.body.rates.map((x: { duration_minutes: number }) => x.duration_minutes)).toEqual([
      30, 45, 60, 75, 90, 120,
    ]);
    // Dollars on screen, cents on the wire.
    expect(req.request.body.rates[2]).toEqual({ duration_minutes: 60, rate_cents: 4500 });
    expect(req.request.body.effective_from).toBe('2026-07-01');
  });

  it('seeds the form from the ladder in force, ignoring closed periods', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.seedRateForm([
      { duration_minutes: 60, rate_cents: 4000, effective_from: '2026-01-01', effective_to: '2026-06-30' },
      { duration_minutes: 60, rate_cents: 5000, effective_from: '2026-07-01', effective_to: null },
    ]);

    expect(p.rateForm[60]).toBe(50);
    // A rung with no open row reads as zero rather than silently reusing an old one.
    expect(p.rateForm[90]).toBe(0);
  });

  // BR-02: the refusal names the appointments in the way, so the front desk
  // knows what to move.
  it('explains an offboard that is blocked by booked appointments', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    selectLocation(p);
    p.offboard({ id: 9, display_name: 'Rin' });

    http
      .expectOne((r) => r.url.endsWith('/staff/9/offboard'))
      .flush(
        { error: { code: 'offboard_blocked', details: { appointment_ids: [4, 5] } } },
        { status: 423, statusText: 'Locked' },
      );

    expect(p.error()).toContain('4, 5');
  });
});
