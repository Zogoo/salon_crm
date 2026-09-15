import { Component, DestroyRef, effect, inject, input, output, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { Subject, debounceTime, distinctUntilChanged, switchMap, tap } from 'rxjs';

import { ClientRecord, PageMeta } from '../core/models';
import { MassagelabService } from '../core/services/massagelab.service';
import { PhonePipe } from '../core/phone';
import { UiIcon } from '../ui';

let nextId = 0;

/**
 * Choose one client out of thousands by typing part of a name or phone number.
 * Shows the best eight matches and how many more there are, so it is obvious
 * when to keep typing. Arrow keys and Enter work; Escape closes the list.
 */
@Component({
  selector: 'app-client-picker',
  imports: [FormsModule, UiIcon, PhonePipe],
  template: `
    @if (chosen(); as c) {
      <div class="picker-chosen" data-testid="client-picked">
        <ui-icon name="person" />
        <span>
          <strong>{{ c.full_name }}</strong>
          <small>{{ c.phone | phone }}{{ c.email ? ' · ' + c.email : '' }}</small>
        </span>
        <button type="button" (click)="clear()" data-testid="client-picker-change">Change</button>
      </div>
    } @else {
      <label class="picker-search">
        <ui-icon name="search" />
        <input
          type="search"
          role="combobox"
          aria-autocomplete="list"
          [attr.aria-expanded]="open()"
          [attr.aria-controls]="listId"
          [attr.aria-label]="label()"
          [placeholder]="placeholder()"
          [(ngModel)]="term"
          (ngModelChange)="terms$.next($event)"
          (focus)="onFocus()"
          (blur)="close()"
          (keydown)="onKey($event)"
          data-testid="client-picker-input"
        />
      </label>
      @if (open()) {
        <ul class="picker-results" role="listbox" [id]="listId" data-testid="client-picker-results">
          @for (c of results(); track c.id; let i = $index) {
            <li
              role="option"
              [class.on]="i === active()"
              [attr.aria-selected]="i === active()"
              (mousedown)="$event.preventDefault()"
              (click)="pick(c)"
              [attr.data-testid]="'client-option-' + c.id"
            >
              <strong>{{ c.full_name }}</strong>
              <small>{{ c.phone | phone }}{{ c.email ? ' · ' + c.email : '' }}</small>
            </li>
          } @empty {
            <li class="picker-note">
              {{ loading() ? 'Searching…' : 'No client matches “' + term + '”.' }}
            </li>
          }
          @if (more() > 0) {
            <li class="picker-note">{{ more() }} more — keep typing to narrow it down.</li>
          }
        </ul>
      }
    }
  `,
  styleUrl: './entity-picker.scss',
})
export class ClientPicker {
  private readonly api = inject(MassagelabService);

  readonly placeholder = input('Name, phone or email');
  readonly label = input('Find a client');
  /** A client who must not be offered (e.g. the one being merged away). */
  readonly excludeId = input<number | null>(null);
  /** A client chosen elsewhere (a rebook link, a client just created) shown as picked. */
  readonly initial = input<ClientRecord | null>(null);
  readonly picked = output<ClientRecord | null>();

  protected readonly listId = `client-picker-${++nextId}`;
  protected readonly chosen = signal<ClientRecord | null>(null);
  protected readonly results = signal<ClientRecord[]>([]);
  protected readonly open = signal(false);
  protected readonly loading = signal(false);
  protected readonly active = signal(0);
  protected readonly more = signal(0);
  protected term = '';
  protected readonly terms$ = new Subject<string>();

  constructor() {
    effect(() => {
      const given = this.initial();
      if (given) this.chosen.set(given);
    });
    this.terms$
      .pipe(
        debounceTime(250),
        distinctUntilChanged(),
        tap(() => {
          this.loading.set(true);
          this.open.set(true);
        }),
        switchMap((q) => this.api.clientList({ q, limit: 8, sort: 'name' })),
        takeUntilDestroyed(inject(DestroyRef)),
      )
      .subscribe({
        next: ({ clients, meta }) => this.show(clients, meta),
        error: () => this.loading.set(false),
      });
  }

  protected onFocus(): void {
    if (!this.results().length) this.terms$.next(this.term);
    this.open.set(true);
  }

  protected close(): void {
    this.open.set(false);
  }

  protected onKey(event: KeyboardEvent): void {
    const count = this.results().length;
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.open.set(true);
      this.active.set(Math.min(this.active() + 1, count - 1));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      this.active.set(Math.max(this.active() - 1, 0));
    } else if (event.key === 'Enter' && this.open() && count) {
      event.preventDefault();
      this.pick(this.results()[this.active()]);
    } else if (event.key === 'Escape') {
      this.close();
    }
  }

  protected pick(client: ClientRecord): void {
    this.chosen.set(client);
    this.open.set(false);
    this.picked.emit(client);
  }

  clear(): void {
    this.chosen.set(null);
    this.term = '';
    this.results.set([]);
    this.picked.emit(null);
  }

  private show(clients: ClientRecord[], meta: PageMeta): void {
    const visible = clients.filter((c) => c.id !== this.excludeId());
    this.results.set(visible);
    this.more.set(Math.max(meta.count - clients.length, 0));
    this.active.set(0);
    this.loading.set(false);
  }
}
