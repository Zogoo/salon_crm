import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { LocationContextService } from '../../core/services/location-context.service';
import { GiftCardsPage } from './giftcards';

describe('Gift cards page', () => {
  let http: HttpTestingController;
  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      imports: [GiftCardsPage],
      providers: [
        provideRouter([]),
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: LocationContextService,
          useValue: {
            load: () => Promise.resolve(),
            current: () => ({ id: 1, name: 'Lawrence' }),
            locations: () => [],
          },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  async function openPage() {
    const fixture = TestBed.createComponent(GiftCardsPage);
    fixture.detectChanges();
    await fixture.whenStable();
    http
      .expectOne((r) => r.url.endsWith('/gift_cards'))
      .flush({ gift_cards: [], meta: { count: 0, page: 1, pages: 1, limit: 25 } });
    await fixture.whenStable();
    return fixture;
  }

  it('opens on look-up, with selling one tap away rather than beside it', async () => {
    const fixture = await openPage();
    const el: HTMLElement = fixture.nativeElement;
    expect(el.querySelector('[data-testid="gc-search"]')).not.toBeNull();
    expect(el.querySelector('[data-testid="gc-new-code"]')).toBeNull();

    (el.querySelector('[data-testid="gc-tab-sell"]') as HTMLButtonElement).click();
    await fixture.whenStable();
    expect(el.querySelector('[data-testid="gc-new-code"]')).not.toBeNull();
    expect(el.querySelector('[data-testid="gc-search"]')).toBeNull();
    // Labels are real words, never translation keys.
    expect(el.textContent).not.toContain('gift_card_form');
  });

  for (const code of ['00123', '']) {
    it(`sends the optional code (${code || 'generated'}) without numeric conversion`, async () => {
      const fixture = await openPage();
      (
        fixture.nativeElement.querySelector('[data-testid="gc-tab-sell"]') as HTMLButtonElement
      ).click();
      await fixture.whenStable();
      const input: HTMLInputElement = fixture.nativeElement.querySelector(
        '[data-testid="gc-new-code"]',
      );
      input.value = code;
      input.dispatchEvent(new Event('input'));
      await fixture.whenStable();
      fixture.nativeElement.querySelector('[data-testid="gc-issue"] button').click();
      const request = http.expectOne((r) => r.method === 'POST' && r.url.endsWith('/gift_cards'));
      expect(request.request.body.gift_card.code).toBe(code);
      request.flush(
        { error: { code: 'validation_failed', message: 'Code has already been taken' } },
        { status: 422, statusText: 'Unprocessable Content' },
      );
      await fixture.whenStable();
      expect(fixture.nativeElement.querySelector('[data-testid="gc-error"]').textContent).toContain(
        'Code has already been taken',
      );
      expect(input.value).toBe(code);
    });
  }
});
