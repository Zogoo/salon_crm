import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { beforeEach, describe, expect, it } from 'vitest';

import { AuditLogPage } from './audit-log';

describe('AuditLogPage', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [AuditLogPage],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    http = TestBed.inject(HttpTestingController);
  });

  it('loads and filters owner audit activity', async () => {
    const fixture = TestBed.createComponent(AuditLogPage);
    fixture.detectChanges();
    http
      .expectOne((request) => request.url.endsWith('/audit_logs'))
      .flush({
        audit_logs: [
          {
            id: 1,
            action: 'payment.recorded',
            auditable_type: 'Payment',
            auditable_id: 2,
            actor: { id: 1, name: 'Owner', email: 'owner@example.com', role: 'owner' },
            changes: { amount_cents: 1000 },
            ip_address: null,
            occurred_at: '2026-09-13T10:00:00Z',
          },
        ],
        meta: { count: 1, page: 1, pages: 1, limit: 50 },
      });
    await fixture.whenStable();
    expect(
      fixture.nativeElement.querySelector('[data-testid="audit-table"]').textContent,
    ).toContain('payment.recorded');

    const input: HTMLInputElement = fixture.nativeElement.querySelector(
      '[data-testid="audit-action"]',
    );
    input.value = 'payment';
    input.dispatchEvent(new Event('input'));
    fixture.nativeElement.querySelector('[data-testid="audit-search"] button').click();
    const request = http.expectOne((candidate) => candidate.url.endsWith('/audit_logs'));
    expect(request.request.params.get('audit_action')).toBe('payment');
    request.flush({ audit_logs: [], meta: { count: 0, page: 1, pages: 1, limit: 50 } });
  });
});
