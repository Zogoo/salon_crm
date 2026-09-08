import { HttpClient, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { describe, expect, it, beforeEach } from 'vitest';

import { ReportsPage } from './reports';

describe('ReportsPage', () => {
  let page: ReportsPage;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()],
    });
    TestBed.inject(HttpClient);
    http = TestBed.inject(HttpTestingController);
    page = TestBed.runInInjectionContext(() => new ReportsPage());
  });

  it('asks for the three operational reports over the chosen range', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    void p.ctx.load();
    http
      .expectOne((r) => r.url.endsWith('/locations'))
      .flush({ locations: [{ id: 7, name: 'Luma', timezone: 'America/Chicago' }] });

    p.from = '2026-08-01';
    p.to = '2026-08-31';
    p.runAll();

    // The range has to travel with the request: a report defaulting to "today"
    // silently answers a different question than the one on screen.
    for (const path of ['no_shows', 'utilization', 'client_retention']) {
      const req = http.expectOne(
        (r) =>
          r.url.endsWith(`/reports/${path}`) &&
          r.params.get('location_id') === '7' &&
          r.params.get('from') === '2026-08-01' &&
          r.params.get('to') === '2026-08-31',
      );
      req.flush({});
    }
  });

  it('turns a rate map into rows the template can iterate', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    expect(p.entries({ Anna: 2, Bo: 1 })).toEqual([
      { key: 'Anna', value: 2 },
      { key: 'Bo', value: 1 },
    ]);
    expect(p.entries({})).toEqual([]);
  });
});
