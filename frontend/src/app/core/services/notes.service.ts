import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { Note, NotesPage } from '../models';

@Injectable({ providedIn: 'root' })
export class NotesService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = `${environment.apiUrl}/notes`;

  list(search = '', page = 1): Observable<NotesPage> {
    let params = new HttpParams().set('page', page);
    if (search) {
      params = params.set('search', search);
    }
    return this.http.get<NotesPage>(this.baseUrl, { params });
  }

  get(id: number): Observable<Note> {
    return this.http.get<Note>(`${this.baseUrl}/${id}`);
  }

  create(note: Pick<Note, 'title' | 'body'>): Observable<Note> {
    return this.http.post<Note>(this.baseUrl, { note });
  }

  update(id: number, note: Pick<Note, 'title' | 'body'>): Observable<Note> {
    return this.http.put<Note>(`${this.baseUrl}/${id}`, { note });
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/${id}`);
  }
}
