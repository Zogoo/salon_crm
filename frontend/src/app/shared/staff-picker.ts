import { Component, DestroyRef, inject, input, output, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { Subject, debounceTime, switchMap, tap } from 'rxjs';

import { PageMeta, StaffMember } from '../core/models';
import { MassagelabService } from '../core/services/massagelab.service';
import { UiIcon } from '../ui';

let nextId = 0;

/**
 * Choose one team member at a location by name or employee code. A location can
 * have hundreds of therapists, which no dropdown can show usefully.
 */
@Component({
  selector: 'app-staff-picker',
  imports: [FormsModule, UiIcon],
  template: `
    @if (chosen(); as s) {
      <div class="picker-chosen" data-testid="staff-picked">
        <ui-icon name="badge" />
        <span>
          <strong>{{ s.display_name }}</strong>
          <small>{{ s.employee_code }}</small>
        </span>
        <button type="button" (click)="clear()" data-testid="staff-picker-change">Change</button>
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
          (blur)="open.set(false)"
          (keydown)="onKey($event)"
          data-testid="staff-picker-input"
        />
      </label>
      @if (open()) {
        <ul class="picker-results" role="listbox" [id]="listId" data-testid="staff-picker-results">
          @for (s of results(); track s.id; let i = $index) {
            <li
              role="option"
              [class.on]="i === active()"
              [attr.aria-selected]="i === active()"
              (mousedown)="$event.preventDefault()"
              (click)="pick(s)"
              [attr.data-testid]="'staff-option-' + s.id"
            >
              <strong>{{ s.display_name }}</strong>
              <small>{{ s.employee_code }}</small>
            </li>
          } @empty {
            <li class="picker-note">
              {{ loading() ? 'Searching…' : 'Nobody at this location matches “' + term + '”.' }}
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
export class StaffPicker {
  private readonly api = inject(MassagelabService);

  readonly locationId = input<number | null>(null);
  readonly role = input<'staff' | 'manager' | ''>('');
  readonly placeholder = input('Name or employee code');
  readonly label = input('Find a team member');
  readonly picked = output<StaffMember | null>();

  protected readonly listId = `staff-picker-${++nextId}`;
  protected readonly chosen = signal<StaffMember | null>(null);
  protected readonly results = signal<StaffMember[]>([]);
  protected readonly open = signal(false);
  protected readonly loading = signal(false);
  protected readonly active = signal(0);
  protected readonly more = signal(0);
  protected term = '';
  protected readonly terms$ = new Subject<string>();

  constructor() {
    this.terms$
      .pipe(
        debounceTime(250),
        tap(() => {
          this.loading.set(true);
          this.open.set(true);
        }),
        switchMap((q) =>
          this.api.staffList({
            q,
            limit: 8,
            sort: 'name',
            status: 'active',
            location_id: this.locationId(),
            role: this.role(),
          }),
        ),
        takeUntilDestroyed(inject(DestroyRef)),
      )
      .subscribe({
        next: ({ staff, meta }) => this.show(staff, meta),
        error: () => this.loading.set(false),
      });
  }

  /** Preselect (e.g. when returning to a report for someone already chosen). */
  select(member: StaffMember | null): void {
    this.chosen.set(member);
  }

  protected onFocus(): void {
    // Opening an empty box lists the first few people, so browsing works too.
    this.terms$.next(this.term);
    this.open.set(true);
  }

  protected onKey(event: KeyboardEvent): void {
    const count = this.results().length;
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.active.set(Math.min(this.active() + 1, count - 1));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      this.active.set(Math.max(this.active() - 1, 0));
    } else if (event.key === 'Enter' && this.open() && count) {
      event.preventDefault();
      this.pick(this.results()[this.active()]);
    } else if (event.key === 'Escape') {
      this.open.set(false);
    }
  }

  protected pick(member: StaffMember): void {
    this.chosen.set(member);
    this.open.set(false);
    this.picked.emit(member);
  }

  clear(): void {
    this.chosen.set(null);
    this.term = '';
    this.results.set([]);
    this.picked.emit(null);
  }

  private show(staff: StaffMember[], meta: PageMeta): void {
    this.results.set(staff);
    this.more.set(Math.max(meta.count - staff.length, 0));
    this.active.set(0);
    this.loading.set(false);
  }
}
