import { Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { TranslatePipe } from '@ngx-translate/core';

import { NotesService } from '../../core/services/notes.service';
import { Note } from '../../core/models';

@Component({
  selector: 'app-notes',
  imports: [ReactiveFormsModule, TranslatePipe],
  templateUrl: './notes.html',
  styleUrl: './notes.scss',
})
export class Notes implements OnInit {
  private readonly fb = inject(FormBuilder);
  private readonly notesService = inject(NotesService);

  protected readonly notes = signal<Note[]>([]);
  protected readonly loading = signal(false);
  protected readonly error = signal('');
  protected readonly editingId = signal<number | null>(null);

  protected readonly form = this.fb.nonNullable.group({
    title: ['', [Validators.required]],
    body: [''],
  });

  ngOnInit(): void {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.notesService.list().subscribe({
      next: (page) => {
        this.notes.set(page.notes);
        this.loading.set(false);
      },
      error: () => {
        this.error.set('Could not load notes');
        this.loading.set(false);
      },
    });
  }

  protected submit(): void {
    if (this.form.invalid) {
      return;
    }

    const payload = this.form.getRawValue();
    const id = this.editingId();
    const request = id ? this.notesService.update(id, payload) : this.notesService.create(payload);

    request.subscribe({
      next: () => {
        this.reset();
        this.load();
      },
      error: (err) => {
        const message = err?.error?.error;
        this.error.set(Array.isArray(message) ? message.join(', ') : (message ?? 'Save failed'));
      },
    });
  }

  protected edit(note: Note): void {
    this.editingId.set(note.id);
    this.form.setValue({ title: note.title, body: note.body ?? '' });
  }

  protected remove(note: Note): void {
    this.notesService.remove(note.id).subscribe({
      next: () => this.load(),
      error: () => this.error.set('Delete failed'),
    });
  }

  protected reset(): void {
    this.editingId.set(null);
    this.error.set('');
    this.form.reset({ title: '', body: '' });
  }
}
