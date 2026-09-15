import { signal } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { ListQuery } from './models';

export type SortDir = 'asc' | 'desc';

export interface ListDefaults<F extends Record<string, string>> {
  sort: string;
  dir: SortDir;
  limit?: number;
  filters: F;
}

/**
 * The state behind every large list: search text, filters, sort and page.
 *
 * It lives in the address bar, so a filtered, sorted page 7 survives a refresh,
 * the Back button returns to exactly where you were after opening a record, and
 * a view can be shared by copying the URL. Search is debounced so typing a name
 * sends one request, not one per keystroke.
 */
export class ListState<F extends Record<string, string>> {
  readonly q = signal('');
  readonly page = signal(1);
  readonly limit = signal(25);
  readonly sort = signal('');
  readonly dir = signal<SortDir>('asc');
  readonly filters = signal<F>({} as F);

  private searchTimer?: ReturnType<typeof setTimeout>;

  constructor(
    private readonly router: Router,
    private readonly route: ActivatedRoute,
    private readonly defaults: ListDefaults<F>,
    private readonly onChange: () => void,
  ) {
    this.sort.set(defaults.sort);
    this.dir.set(defaults.dir);
    this.limit.set(defaults.limit ?? 25);
    this.filters.set({ ...defaults.filters });
  }

  /** Call once on init: take whatever the URL says, fall back to defaults. */
  readFromUrl(): void {
    const params = this.route.snapshot.queryParamMap;
    this.q.set(params.get('q') ?? '');
    this.page.set(Math.max(Number(params.get('page')) || 1, 1));
    this.limit.set(Number(params.get('limit')) || this.defaults.limit || 25);
    this.sort.set(params.get('sort') ?? this.defaults.sort);
    this.dir.set(
      params.get('dir') === 'desc'
        ? 'desc'
        : params.get('dir') === 'asc'
          ? 'asc'
          : this.defaults.dir,
    );
    const filters = { ...this.defaults.filters };
    for (const key of Object.keys(filters)) {
      const value = params.get(key);
      if (value !== null) (filters as Record<string, string>)[key] = value;
    }
    this.filters.set(filters);
  }

  query(): ListQuery {
    return {
      q: this.q().trim(),
      page: this.page(),
      limit: this.limit(),
      sort: this.sort(),
      dir: this.dir(),
      ...this.filters(),
    };
  }

  search(term: string): void {
    this.q.set(term);
    clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => this.changed(true), 300);
  }

  /** A header clicked once sorts ascending; clicked again, descending. */
  sortBy(key: string): void {
    if (this.sort() === key) this.dir.set(this.dir() === 'asc' ? 'desc' : 'asc');
    else {
      this.sort.set(key);
      this.dir.set('asc');
    }
    this.changed(true);
  }

  setFilter(key: keyof F, value: string): void {
    this.filters.update((f) => ({ ...f, [key]: value }));
    this.changed(true);
  }

  goTo(page: number): void {
    this.page.set(page);
    this.changed(false);
  }

  setLimit(limit: number): void {
    this.limit.set(limit);
    this.changed(true);
  }

  clear(): void {
    this.q.set('');
    this.filters.set({ ...this.defaults.filters });
    this.changed(true);
  }

  /** True when anything narrows the list, so the screen can say so and offer Clear. */
  isFiltered(): boolean {
    return (
      !!this.q().trim() ||
      Object.entries(this.filters()).some(
        ([key, value]) => value !== (this.defaults.filters as Record<string, string>)[key],
      )
    );
  }

  ariaSort(key: string): 'ascending' | 'descending' | 'none' {
    if (this.sort() !== key) return 'none';
    return this.dir() === 'asc' ? 'ascending' : 'descending';
  }

  sortIcon(key: string): string {
    if (this.sort() !== key) return 'unfold_more';
    return this.dir() === 'asc' ? 'arrow_upward' : 'arrow_downward';
  }

  private changed(resetPage: boolean): void {
    if (resetPage) this.page.set(1);
    const filters = Object.fromEntries(
      Object.entries(this.filters()).map(([key, value]) => [
        key,
        value === (this.defaults.filters as Record<string, string>)[key] ? null : value,
      ]),
    );
    void this.router.navigate([], {
      relativeTo: this.route,
      replaceUrl: true,
      // Merge, so a screen's own parameters (a tab, a mode) survive list changes.
      queryParamsHandling: 'merge',
      queryParams: {
        q: this.q().trim() || null,
        page: this.page() > 1 ? this.page() : null,
        limit: this.limit() !== (this.defaults.limit ?? 25) ? this.limit() : null,
        sort: this.sort() !== this.defaults.sort ? this.sort() : null,
        dir: this.dir() !== this.defaults.dir ? this.dir() : null,
        ...filters,
      },
    });
    this.onChange();
  }
}
