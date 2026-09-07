import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';

import { NotesService } from './notes.service';
import { environment } from '../../../environments/environment';

describe('NotesService', () => {
  let service: NotesService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });

    service = TestBed.inject(NotesService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('requests the first page without a search term', () => {
    service.list().subscribe((page) => expect(page.notes.length).toBe(1));

    const req = http.expectOne(`${environment.apiUrl}/notes?page=1`);
    expect(req.request.method).toBe('GET');

    req.flush({
      notes: [{ id: 1, title: 'First', body: null, created_at: '', updated_at: '' }],
      meta: { count: 1, page: 1, pages: 1, limit: 20 },
    });
  });

  it('passes the search term through', () => {
    service.list('todo').subscribe();

    const req = http.expectOne(`${environment.apiUrl}/notes?page=1&search=todo`);
    req.flush({ notes: [], meta: { count: 0, page: 1, pages: 1, limit: 20 } });
  });

  it('wraps the payload in a note key on create', () => {
    service.create({ title: 'New', body: 'Body' }).subscribe();

    const req = http.expectOne(`${environment.apiUrl}/notes`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ note: { title: 'New', body: 'Body' } });

    req.flush({ id: 1, title: 'New', body: 'Body', created_at: '', updated_at: '' });
  });
});
