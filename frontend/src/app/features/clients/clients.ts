import { PhonePipe } from '../../core/phone';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Subscription } from 'rxjs';

import { ListState } from '../../core/list-state';
import { ClientRecord, PageMeta } from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import {
  UiBanner,
  UiButton,
  UiChip,
  UiDialog,
  UiEmpty,
  UiField,
  UiIcon,
  UiPage,
  UiPaginator,
} from '../../ui';

type ClientFilters = {
  membership: string;
  visited: string;
  no_shows: string;
  location_id: string;
};

/**
 * FRS §11 — the client directory, built for thousands of records: searched,
 * filtered, sorted and paged on the server. Opening a client goes to their own
 * page, so the list keeps its place when you come back.
 */
@Component({
  selector: 'app-clients',
  imports: [
    PhonePipe,
    FormsModule,
    DecimalPipe,
    RouterLink,
    WallClockPipe,
    UiPage,
    UiButton,
    UiIcon,
    UiChip,
    UiEmpty,
    UiBanner,
    UiPaginator,
    UiDialog,
    UiField,
  ],
  templateUrl: './clients.html',
  styleUrls: ['../../ui/layouts.scss', '../../ui/data-table.scss', './clients.scss'],
})
export class ClientsPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  protected readonly ctx = inject(LocationContextService);

  protected readonly rows = signal<ClientRecord[]>([]);
  protected readonly meta = signal<PageMeta | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly creating = signal(false);
  protected readonly createError = signal<string | null>(null);
  protected readonly saving = signal(false);
  protected newClient = this.emptyClient();

  protected readonly list = new ListState<ClientFilters>(
    this.router,
    this.route,
    {
      sort: 'name',
      dir: 'asc',
      filters: { membership: '', visited: '', no_shows: '', location_id: '' },
    },
    () => this.load(),
  );

  protected readonly skeleton = Array.from({ length: 6 });
  private request?: Subscription;

  /** What the list is narrowed to, in words — never leave someone guessing why rows are missing. */
  protected readonly summary = computed(() => {
    const f = this.list.filters();
    const parts: string[] = [];
    if (f.membership === 'member') parts.push('members');
    if (f.membership === 'not_member') parts.push('non-members');
    if (f.visited === 'recent') parts.push('visited in the last 90 days');
    if (f.visited === 'lapsed') parts.push('not visited in 90 days');
    if (f.visited === 'never') parts.push('never visited');
    if (f.no_shows === 'true') parts.push('with no-shows');
    if (f.location_id) {
      const name = this.ctx.locations().find((l) => String(l.id) === f.location_id)?.name;
      parts.push(`preferring ${name ?? 'one location'}`);
    }
    if (this.list.q().trim()) parts.push(`matching “${this.list.q().trim()}”`);
    return parts.join(' · ');
  });

  ngOnInit(): void {
    this.list.readFromUrl();
    void this.ctx.load();
    this.load();
  }

  protected load(): void {
    this.request?.unsubscribe();
    this.loading.set(true);
    this.error.set(null);
    this.request = this.api.clientList(this.list.query()).subscribe({
      next: ({ clients, meta }) => {
        this.rows.set(clients);
        this.meta.set(meta);
        this.loading.set(false);
      },
      error: () => {
        this.error.set('Could not load clients. Check the connection and try again.');
        this.loading.set(false);
      },
    });
  }

  protected toggleNoShows(): void {
    this.list.setFilter('no_shows', this.list.filters().no_shows === 'true' ? '' : 'true');
  }

  // --- new client ---------------------------------------------------------

  protected openCreate(): void {
    this.newClient = this.emptyClient();
    this.createError.set(null);
    this.creating.set(true);
  }

  protected createClient(): void {
    const c = this.newClient;
    if (!c.first_name.trim() || !c.last_name.trim() || !c.phone.trim()) {
      this.createError.set('First name, last name and phone are required.');
      return;
    }
    this.saving.set(true);
    this.createError.set(null);
    this.api
      .createClient({
        first_name: c.first_name.trim(),
        last_name: c.last_name.trim(),
        phone: c.phone.trim(),
        email: c.email.trim() || null,
      })
      .subscribe({
        next: (created) => {
          this.saving.set(false);
          this.creating.set(false);
          void this.router.navigate(['/clients', created.id]);
        },
        error: (err) => {
          this.saving.set(false);
          const body = err?.error?.error;
          this.createError.set(
            Array.isArray(body) ? body.join('. ') : 'Could not create the client.',
          );
        },
      });
  }

  private emptyClient() {
    return { first_name: '', last_name: '', phone: '', email: '' };
  }
}
