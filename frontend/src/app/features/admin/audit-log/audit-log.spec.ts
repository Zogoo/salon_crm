import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AuditLogPage } from './audit-log';

describe('AuditLogPage', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [AuditLogPage],
      providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()],
    });
    http = TestBed.inject(HttpTestingController);
  });

  it('reads as sentences, pages 50 at a time, and searches as you type', async () => {
    vi.useFakeTimers();
    const fixture = TestBed.createComponent(AuditLogPage);
    fixture.detectChanges();
    const first = http.expectOne((request) => request.url.endsWith('/audit_logs'));
    expect(first.request.params.get('limit')).toBe('50');
    first.flush({
      audit_logs: [
        {
          id: 1,
          action: 'payment.recorded',
          auditable_type: 'GiftCard',
          auditable_id: 2,
          actor: { id: 1, name: 'Owner', email: 'owner@example.com', role: 'owner' },
          changes: { amount_cents: 1000 },
          ip_address: null,
          occurred_at: '2026-09-13T10:00:00-05:00',
        },
      ],
      meta: { count: 1, page: 1, pages: 1, limit: 50 },
    });
    fixture.detectChanges();

    const table: HTMLElement = fixture.nativeElement.querySelector('[data-testid="audit-table"]');
    expect(table.textContent).toContain('Payment recorded');
    expect(table.textContent).toContain('Gift card #2');
    expect(table.textContent).toContain('Amount: $10.00');

    const input: HTMLInputElement = fixture.nativeElement.querySelector(
      '[data-testid="audit-action"]',
    );
    input.value = 'payment';
    input.dispatchEvent(new Event('input'));
    vi.advanceTimersByTime(350);
    const request = http.expectOne((candidate) => candidate.url.endsWith('/audit_logs'));
    expect(request.request.params.get('audit_action')).toBe('payment');
    request.flush({ audit_logs: [], meta: { count: 0, page: 1, pages: 1, limit: 50 } });
    vi.useRealTimers();
  });
});
