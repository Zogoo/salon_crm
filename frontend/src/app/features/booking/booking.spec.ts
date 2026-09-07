import { HttpClient } from '@angular/common/http';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { describe, expect, it, beforeEach } from 'vitest';

import { Service } from '../../core/models';
import { BookingPage } from './booking';

const MENU: Service[] = [
  {
    id: 1,
    name: 'Deep Tissue',
    kind: 'standard',
    category: 'massage',
    category_position: 1,
    variants: [
      {
        id: 11,
        duration_minutes: 60,
        price_cents: 8000,
        therapist_count: 1,
        required_client_capacity: 1,
        requires_room_type: null,
      },
    ],
  },
  {
    id: 2,
    name: 'Couples',
    kind: 'standard',
    category: 'massage',
    category_position: 1,
    variants: [
      {
        id: 21,
        duration_minutes: 90,
        price_cents: 23000,
        therapist_count: 2,
        required_client_capacity: 2,
        requires_room_type: null,
      },
    ],
  },
  {
    id: 3,
    name: 'Scalp massage',
    kind: 'add_on',
    category: 'add_on',
    category_position: 5,
    variants: [
      {
        id: 31,
        duration_minutes: 30,
        price_cents: 3500,
        therapist_count: 1,
        required_client_capacity: 1,
        requires_room_type: null,
      },
    ],
  },
];

describe('BookingPage', () => {
  let page: BookingPage;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()],
    });
    TestBed.inject(HttpClient);
    page = TestBed.runInInjectionContext(() => new BookingPage());
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (page as any).services.set(MENU);
  });

  // The bug this covers: totals were a computed() over plain fields, so they
  // never recalculated and the screen always showed $0.00.
  it('recalculates the total when the service changes', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    expect(p.totalCents()).toBe(0);

    p.onVariantChange(11);
    expect(p.totalCents()).toBe(8000);

    p.toggle('addOnIds', 31, true);
    expect(p.totalCents()).toBe(11500);
    expect(p.variantIds()).toEqual([11, 31]);

    p.toggle('addOnIds', 31, false);
    expect(p.totalCents()).toBe(8000);
  });

  it('asks for a second client only when the service seats two', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.onVariantChange(11);
    expect(p.needsTwoClients()).toBe(false);

    p.onVariantChange(21);
    expect(p.needsTwoClients()).toBe(true);
  });

  it('clears a chosen slot when the service changes, so a stale time cannot be booked', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.selectedSlot = { start_at: '2026-09-07T09:00:00-05:00' };
    p.onVariantChange(21);
    expect(p.selectedSlot).toBeNull();
  });
});
