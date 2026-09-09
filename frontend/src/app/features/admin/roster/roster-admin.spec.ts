import { HttpClient, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { describe, expect, it, beforeEach } from 'vitest';

import { RosterAdminPage } from './roster-admin';

describe('RosterAdminPage', () => {
  let page: RosterAdminPage;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()],
    });
    TestBed.inject(HttpClient);
    http = TestBed.inject(HttpTestingController);
    page = TestBed.runInInjectionContext(() => new RosterAdminPage());
  });

  // BR-07: the API answers with the appointments that would be left uncovered,
  // which is the only part the person editing can act on.
  it('names the appointments a shortened shift would strand', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.editing = { id: 12 };
    p.edit = { work_date: '2026-09-09', starts_at: '14:00', ends_at: '22:00' };
    p.saveEdit();

    http
      .expectOne((r) => r.url.endsWith('/shifts/12'))
      .flush(
        { error: { code: 'would_orphan_appointments', details: { appointment_ids: [31] } } },
        { status: 422, statusText: 'Unprocessable Content' },
      );

    expect(p.error()).toContain('31');
    expect(p.editing).not.toBeNull();
  });

  // Publishing is all-or-nothing: a half-published week leaves some therapists
  // silently unbookable.
  it('reports that nothing was published when one shift clashes', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    p.selectedIds.set([1, 2]);
    p.publish();

    http
      .expectOne((r) => r.url.endsWith('/shifts/publish'))
      .flush(
        { error: { code: 'shift_conflict', details: { conflicts: [{ shift_id: 2, errors: ['overlaps'] }] } } },
        { status: 409, statusText: 'Conflict' },
      );

    expect(p.error()).toContain('Nothing was published');
    expect(p.error()).toContain('2');
  });

  it('reads the wall clock off the string rather than converting zones', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const p = page as any;
    expect(p.wallClock('2026-09-09T09:00:00-05:00')).toBe('09:00');
  });
});
