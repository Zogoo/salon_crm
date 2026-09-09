import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideTranslateService } from '@ngx-translate/core';

import { App } from './app';

describe('App', () => {
  beforeEach(async () => {
    localStorage.clear();

    await TestBed.configureTestingModule({
      imports: [App],
      providers: [
        provideRouter([]),
        provideHttpClient(),
        provideHttpClientTesting(),
        provideTranslateService(),
      ],
    }).compileComponents();
  });

  it('creates the app', () => {
    const fixture = TestBed.createComponent(App);
    expect(fixture.componentInstance).toBeTruthy();
  });

  it('offers no destinations until someone is signed in', async () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    await fixture.whenStable();

    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('.appbar__brand')?.textContent).toContain('Massagelab');
    // Navigation is built from the signed-in role, so an anonymous visitor is
    // shown nothing to click rather than links that would 403.
    expect(compiled.querySelectorAll('.drawer__link')).toHaveLength(0);
    expect(compiled.querySelector('[data-testid="current-role"]')).toBeNull();
    TestBed.inject(HttpTestingController).verify();
  });
});
