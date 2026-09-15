import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { AuthService } from '../../core/services/auth.service';
import { LocationContextService } from '../../core/services/location-context.service';
import { ClientDetailPage } from './client-detail';
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
  last_visit_at: '2026-09-01T10:00:00-05:00',
  visits_count: 4,
  member: true,
  preferred_location: { id: 7, name: 'Luma' },
};

const meta = { count: 2008, page: 1, pages: 81, limit: 25, sort: 'name', dir: 'asc' };

describe('Clients directory', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      imports: [ClientsPage],
      providers: [
        provideRouter([]),
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: LocationContextService,
          useValue: { load: () => Promise.resolve(), locations: () => [] },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  it('asks the server for one page, and says where in the whole list it is', async () => {
    const fixture = TestBed.createComponent(ClientsPage);
    fixture.detectChanges();

    const request = http.expectOne((r) => r.url.endsWith('/clients'));
    expect(request.request.params.get('page')).toBe('1');
    expect(request.request.params.get('limit')).toBe('25');
    expect(request.request.params.get('sort')).toBe('name');
    request.flush({ clients: [client], meta });
    await fixture.whenStable();

    const el: HTMLElement = fixture.nativeElement;
    expect(el.querySelector('[data-testid="pager-range"]')?.textContent).toContain('1–25 of 2,008');
    const row = el.querySelector('[data-testid="client-row-1"]');
    expect(row?.textContent).toContain('Test Client');
    expect(row?.textContent).toContain('Member');
    expect(row?.getAttribute('href')).toBe('/clients/1');
  });

  it('sends filters to the server and resets to the first page', async () => {
    const fixture = TestBed.createComponent(ClientsPage);
    fixture.detectChanges();
    http.expectOne((r) => r.url.endsWith('/clients')).flush({ clients: [client], meta });
    await fixture.whenStable();

    (
      fixture.nativeElement.querySelector('[data-testid="filter-no-shows"]') as HTMLButtonElement
    ).click();
    const filtered = http.expectOne((r) => r.url.endsWith('/clients'));
    expect(filtered.request.params.get('no_shows')).toBe('true');
    expect(filtered.request.params.get('page')).toBe('1');
    filtered.flush({ clients: [], meta: { ...meta, count: 0, pages: 1 } });
    await fixture.whenStable();

    const el: HTMLElement = fixture.nativeElement;
    expect(el.querySelector('[data-testid="clients-summary"]')?.textContent).toContain(
      'with no-shows',
    );
    expect(el.textContent).toContain('No clients match');
  });
});

describe('Client record', () => {
  let http: HttpTestingController;
  let role = 'owner';

  function setup() {
    TestBed.configureTestingModule({
      imports: [ClientDetailPage],
      providers: [
        provideRouter([]),
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: { user: () => ({ role }) } },
        {
          provide: ActivatedRoute,
          useValue: {
            paramMap: of(convertToParamMap({ id: '1' })),
            snapshot: { queryParamMap: convertToParamMap({}) },
          },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
  }

  afterEach(() => http.verify());

  it('pages the visit history and shows each visit’s rating beside it', async () => {
    role = 'owner';
    setup();
    const fixture = TestBed.createComponent(ClientDetailPage);
    fixture.detectChanges();

    http.expectOne((r) => r.url.endsWith('/clients/1')).flush({ ...client, appointments: [] });
    http
      .expectOne((r) => r.url.endsWith('/clients/1/history_summary'))
      .flush({
        visits: 14,
        lifetime_spend_cents: 120000,
        last_visit: '2026-09-01T10:00:00-05:00',
        days_since_last_visit: 14,
        favourite_service: 'Deep Tissue',
        favourite_therapist: 'Anna',
      });
    const visits = http.expectOne((r) => r.url.endsWith('/clients/1/appointments'));
    expect(visits.request.params.get('limit')).toBe('10');
    visits.flush({
      appointments: [
        {
          id: 11,
          reference: 'APT-11',
          status: 'completed',
          location: 'Lawrence',
          starts_at: '2026-09-01T10:00:00-05:00',
          therapists: ['Anna'],
          total_price_cents: 8000,
        },
      ],
      meta: { count: 14, page: 1, pages: 2, limit: 10 },
    });
    http
      .expectOne((r) => r.url.endsWith('/clients/1/ratings'))
      .flush({
        ratings: [
          { id: 3, appointment_id: 11, score: 9, comment: null, therapist: 'Anna', created_at: '' },
        ],
      });
    await fixture.whenStable();

    const el: HTMLElement = fixture.nativeElement;
    expect(el.querySelector('[data-testid="visit-11"]')?.textContent).toContain('9 / 10');
    expect(el.querySelector('[data-testid="pager-range"]')?.textContent).toContain('1–10 of 14');
    expect(el.textContent).toContain('$1200.00');
    // One place for every action on the record.
    expect(
      el.querySelector('[data-testid="client-actions"] [data-testid="client-book"]'),
    ).not.toBeNull();
    expect(el.querySelector('[data-testid="client-merge"]')).not.toBeNull();
  });

  it('keeps money and the Owner-only merge away from a Manager’s view where appropriate', async () => {
    role = 'manager';
    setup();
    const fixture = TestBed.createComponent(ClientDetailPage);
    fixture.detectChanges();
    http.expectOne((r) => r.url.endsWith('/clients/1')).flush({ ...client, appointments: [] });
    http
      .expectOne((r) => r.url.endsWith('/history_summary'))
      .flush({ visits: 0, lifetime_spend_cents: 0 });
    http
      .expectOne((r) => r.url.endsWith('/appointments'))
      .flush({ appointments: [], meta: { count: 0, page: 1, pages: 1, limit: 10 } });
    http.expectOne((r) => r.url.endsWith('/ratings')).flush({ ratings: [] });
    await fixture.whenStable();

    expect(fixture.nativeElement.querySelector('[data-testid="client-merge"]')).toBeNull();
    expect(fixture.nativeElement.querySelector('[data-testid="tab-orders"]')).not.toBeNull();
  });
});
