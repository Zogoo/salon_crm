import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { AuthService } from '../../core/services/auth.service';
import { ClientsPage } from './clients';

const client = {
  id: 1,
  first_name: 'Test',
  last_name: 'Client',
  full_name: 'Test Client',
  phone: '+13125550001',
  email: null,
  no_show_count: 0,
  late_cancel_count: 0,
};

describe('Client history improvements', () => {
  let http: HttpTestingController;
  let role = 'owner';
  beforeEach(() => {
    role = 'owner';
    localStorage.clear();
    TestBed.configureTestingModule({
      imports: [ClientsPage],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: { user: () => ({ role }) } },
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  it('renders ratings beside their visits and purchased gift-card balances', async () => {
    const fixture = TestBed.createComponent(ClientsPage);
    fixture.detectChanges();
    http.expectOne((r) => r.url.endsWith('/clients')).flush({ clients: [client] });
    await fixture.whenStable();
    fixture.nativeElement.querySelector('[data-testid="client-1"]').click();
    http
      .expectOne((r) => r.url.endsWith('/clients/1'))
      .flush({
        ...client,
        appointments: [
          {
            id: 11,
            reference: 'APT-11',
            starts_at: '2026-09-14T10:00:00-05:00',
            location: 'Lawrence',
            therapists: ['Therapist'],
            status: 'completed',
          },
          {
            id: 12,
            reference: 'APT-12',
            starts_at: '2026-09-15T10:00:00-05:00',
            location: 'Lawrence',
            therapists: ['Therapist'],
            status: 'scheduled',
          },
        ],
      });
    http
      .expectOne((r) => r.url.endsWith('/clients/1/ratings'))
      .flush({
        ratings: [
          {
            id: 3,
            appointment_id: 11,
            score: 9,
            comment: 'Good',
            therapist: 'Therapist',
            created_at: '2026-09-14T11:00:00-05:00',
          },
        ],
      });
    http
      .expectOne((r) => r.url.endsWith('/clients/1/gift_cards'))
      .flush({
        gift_cards: [
          {
            id: 4,
            code: '00123',
            initial_value_cents: 10000,
            balance_cents: 6500,
            status: 'active',
            sold_at: '2026-09-14T10:00:00-05:00',
            sold_at_location: 'Lawrence',
          },
        ],
      });
    http.expectOne((r) => r.url.endsWith('/clients/1/orders')).flush({ orders: [] });
    http
      .expectOne((r) => r.url.endsWith('/clients/1/preferences/versions'))
      .flush({ versions: [] });
    http
      .expectOne((r) => r.url.endsWith('/clients/1/history_summary'))
      .flush({
        lifetime_spend_cents: 0,
        favourite_service: null,
        favourite_therapist: null,
      });
    await fixture.whenStable();
    const rows = fixture.nativeElement.querySelectorAll('[data-testid="client-visits"] tbody tr');
    expect(rows[0].textContent).toContain('9 / 10');
    expect(rows[1].textContent).not.toContain('9 / 10');
    const cards = fixture.nativeElement.querySelector('[data-testid="client-gift-cards"]');
    expect(cards.textContent).toContain('00123');
    expect(cards.textContent).toContain('$65.00');
  });

  it('does not request protected financial or ratings history for staff', async () => {
    role = 'staff';
    const fixture = TestBed.createComponent(ClientsPage);
    fixture.detectChanges();
    http.expectOne((r) => r.url.endsWith('/clients')).flush({ clients: [client] });
    await fixture.whenStable();
    fixture.nativeElement.querySelector('[data-testid="client-1"]').click();
    http.expectOne((r) => r.url.endsWith('/clients/1')).flush({ ...client, appointments: [] });
    http.expectNone((r) => /\/(ratings|gift_cards)$/.test(r.url));
    await fixture.whenStable();
    expect(fixture.nativeElement.querySelector('[data-testid="client-gift-cards"]')).toBeNull();
  });
});
