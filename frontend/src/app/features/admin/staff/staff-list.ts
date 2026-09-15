import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Subscription } from 'rxjs';

import { ListState } from '../../../core/list-state';
import { PageMeta, StaffMember } from '../../../core/models';
import { LocationContextService } from '../../../core/services/location-context.service';
import { MassagelabService } from '../../../core/services/massagelab.service';
import {
  UiBanner,
  UiButton,
  UiChip,
  UiEmpty,
  UiIcon,
  UiPage,
  UiPaginator,
  humanise,
  statusTone,
} from '../../../ui';

type StaffFilters = { status: string; role: string };

/**
 * Doc 01 §3.1 — the team at the selected location, paged and searchable so a
 * location with hundreds of therapists is as quick to work with as one with
 * four. Opening someone goes to their own record.
 */
@Component({
  selector: 'app-staff-list',
  imports: [
    FormsModule,
    RouterLink,
    UiPage,
    UiButton,
    UiIcon,
    UiChip,
    UiEmpty,
    UiBanner,
    UiPaginator,
  ],
  templateUrl: './staff-list.html',
  styleUrls: ['../../../ui/layouts.scss', '../../../ui/data-table.scss', './staff.scss'],
})
export class StaffListPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  protected readonly ctx = inject(LocationContextService);

  protected readonly rows = signal<StaffMember[]>([]);
  protected readonly meta = signal<PageMeta | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly skeleton = Array.from({ length: 6 });
  private request?: Subscription;

  protected readonly list = new ListState<StaffFilters>(
    this.router,
    this.route,
    { sort: 'name', dir: 'asc', filters: { status: 'active', role: '' } },
    () => this.load(),
  );

  protected readonly subtitle = computed(
    () =>
      `Everyone who works at ${this.ctx.current()?.name ?? 'this location'}. Switch location in the top bar to see another team.`,
  );

  protected readonly summary = computed(() => {
    const f = this.list.filters();
    const parts: string[] = [];
    if (f.status === 'offboarded') parts.push('offboarded');
    if (f.status === 'all') parts.push('including offboarded');
    if (f.role === 'staff') parts.push('therapists');
    if (f.role === 'manager') parts.push('managers');
    if (this.list.q().trim()) parts.push(`matching “${this.list.q().trim()}”`);
    return parts.join(' · ');
  });

  protected humanStatus = humanise;
  protected tone = statusTone;

  ngOnInit(): void {
    this.list.readFromUrl();
    void this.ctx.load().then(() => this.load());
  }

  protected roleLabel(member: StaffMember): string {
    return member.role === 'manager' ? 'Manager' : 'Therapist';
  }

  protected load(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.request?.unsubscribe();
    this.loading.set(true);
    this.error.set(null);
    this.request = this.api.staffList({ ...this.list.query(), location_id: loc.id }).subscribe({
      next: ({ staff, meta }) => {
        this.rows.set(staff);
        this.meta.set(meta);
        this.loading.set(false);
      },
      error: () => {
        this.error.set('Could not load the team. Check the connection and try again.');
        this.loading.set(false);
      },
    });
  }
}
