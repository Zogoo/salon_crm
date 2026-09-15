import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { beforeEach, describe, expect, it } from 'vitest';

import { LocationContextService } from '../../../core/services/location-context.service';
import { CatalogueAdminPage } from './catalogue-admin';

describe('CatalogueAdminPage editing', () => {
  let page: any;
  let http: HttpTestingController;
  const service = {
    id: 1,
    name: 'Swedish',
    kind: 'standard',
    active: true,
    service_category_id: 1,
    variants: [],
  };

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: LocationContextService, useValue: { current: () => ({ id: 2 }) } },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    page = TestBed.runInInjectionContext(() => new CatalogueAdminPage());
  });

  it('updates an existing service name through the existing API', () => {
    page.serviceForm = { name: 'Classic Swedish', kind: 'standard', service_category_id: 1 };
    page.saveService(service);
    const request = http.expectOne((candidate) => candidate.url.endsWith('/services/1'));
    expect(request.request.method).toBe('PATCH');
    expect(request.request.body.service.name).toBe('Classic Swedish');
    request.flush({ ...service, name: 'Classic Swedish' });
    http.expectOne((candidate) => candidate.url.endsWith('/services')).flush({ services: [] });
    expect(page.detail().name).toBe('Classic Swedish');
  });

  it('updates an existing service duration', () => {
    const variant = {
      id: 8,
      duration_minutes: 60,
      therapist_count: 1,
      required_client_capacity: 1,
      requires_room_type: null,
      active: true,
    };
    page.variantForm = { ...variant, duration_minutes: 75 };
    page.saveVariant(service, variant);
    const request = http.expectOne((candidate) => candidate.url.endsWith('/service_variants/8'));
    expect(request.request.body.service_variant.duration_minutes).toBe(75);
    request.flush({ ...variant, duration_minutes: 75 });
    http
      .expectOne((candidate) => candidate.url.endsWith('/services/1'))
      .flush({ ...service, variants: [{ ...variant, duration_minutes: 75 }] });
  });
});
