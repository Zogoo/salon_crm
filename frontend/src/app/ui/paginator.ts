import { Component, computed, input, output } from '@angular/core';

import { PageMeta } from '../core/models';
import { UiIcon } from './icon';

/**
 * Footer for every long list: where you are ("26–50 of 2,000"), how many rows a
 * page shows, and first / previous / next / last. The range is spelled out so
 * nobody has to work out how much is left.
 */
@Component({
  selector: 'ui-paginator',
  imports: [UiIcon],
  template: `
    <nav class="pager" aria-label="Pagination" data-testid="pager">
      <span class="pager__range" data-testid="pager-range">{{ range() }}</span>
      <label class="pager__size">
        <span>Rows per page</span>
        <select (change)="changeLimit($event)" data-testid="pager-size">
          @for (n of sizes(); track n) {
            <option [value]="n" [selected]="n === meta()?.limit">{{ n }}</option>
          }
        </select>
      </label>
      <span class="pager__page">Page {{ page() }} of {{ pages() }}</span>
      <span class="pager__buttons">
        <button
          type="button"
          (click)="go(1)"
          [disabled]="page() <= 1"
          aria-label="First page"
          data-testid="pager-first"
        >
          <ui-icon name="first_page" />
        </button>
        <button
          type="button"
          (click)="go(page() - 1)"
          [disabled]="page() <= 1"
          aria-label="Previous page"
          data-testid="pager-prev"
        >
          <ui-icon name="chevron_left" />
        </button>
        <button
          type="button"
          (click)="go(page() + 1)"
          [disabled]="page() >= pages()"
          aria-label="Next page"
          data-testid="pager-next"
        >
          <ui-icon name="chevron_right" />
        </button>
        <button
          type="button"
          (click)="go(pages())"
          [disabled]="page() >= pages()"
          aria-label="Last page"
          data-testid="pager-last"
        >
          <ui-icon name="last_page" />
        </button>
      </span>
    </nav>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    .pager {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: flex-end;
      gap: var(--sp-2) var(--sp-4);
      padding: var(--sp-2) var(--sp-4);
      @include type-body-sm;
      color: var(--md-on-surface-variant);
    }
    .pager__range {
      margin-right: auto;
      color: var(--md-on-surface);
      font-weight: 600;
      font-variant-numeric: tabular-nums;
    }
    .pager__size {
      display: inline-flex;
      align-items: center;
      gap: var(--sp-2);
      select {
        min-height: 2.25rem;
        padding: 0 var(--sp-2);
        border: 1px solid var(--md-outline);
        border-radius: var(--md-shape-xs);
        background: var(--md-surface);
        color: var(--md-on-surface);
        font: inherit;
      }
    }
    .pager__buttons {
      display: inline-flex;
      gap: var(--sp-1);
      button {
        display: grid;
        place-items: center;
        width: 2.75rem;
        height: 2.75rem;
        border: 0;
        border-radius: 999px;
        background: transparent;
        color: var(--md-on-surface);
        cursor: pointer;
      }
      button:hover:not(:disabled) {
        background: var(--md-surface-container-high);
      }
      button:disabled {
        color: var(--md-outline-variant);
        cursor: default;
      }
    }
    @include compact-only {
      .pager__size,
      .pager__page {
        display: none;
      }
    }
  `,
})
export class UiPaginator {
  readonly meta = input<PageMeta | null>(null);
  readonly sizes = input<number[]>([25, 50, 100]);
  readonly pageChange = output<number>();
  readonly limitChange = output<number>();

  protected readonly page = computed(() => this.meta()?.page ?? 1);
  protected readonly pages = computed(() => Math.max(this.meta()?.pages ?? 1, 1));
  protected readonly range = computed(() => {
    const m = this.meta();
    if (!m || !m.count) return 'No results';
    const first = (m.page - 1) * m.limit + 1;
    const last = Math.min(m.page * m.limit, m.count);
    return `${first.toLocaleString('en-US')}–${last.toLocaleString('en-US')} of ${m.count.toLocaleString('en-US')}`;
  });

  protected go(page: number): void {
    const target = Math.min(Math.max(page, 1), this.pages());
    if (target !== this.page()) this.pageChange.emit(target);
  }

  protected changeLimit(event: Event): void {
    this.limitChange.emit(Number((event.target as HTMLSelectElement).value));
  }
}
