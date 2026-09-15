import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { ListState } from '../../../core/list-state';
import { AuditLogRecord, PageMeta } from '../../../core/models';
import { WallClockPipe } from '../../../core/pipes/wall-clock.pipe';
import { MassagelabService } from '../../../core/services/massagelab.service';
import { UiBanner, UiEmpty, UiIcon, UiPage, UiPaginator, humanise } from '../../../ui';

type AuditFilters = { auditable_type: string; from: string; to: string };

/** Every sensitive read and business change, newest first — thousands of rows, paged. */
@Component({
  selector: 'app-audit-log',
  imports: [FormsModule, WallClockPipe, UiPage, UiIcon, UiEmpty, UiBanner, UiPaginator],
  templateUrl: './audit-log.html',
  styleUrls: ['../../../ui/layouts.scss', '../../../ui/data-table.scss', './audit-log.scss'],
})
export class AuditLogPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected readonly logs = signal<AuditLogRecord[]>([]);
  protected readonly meta = signal<PageMeta | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  private request?: Subscription;

  /** The records that are audited, by the name the desk knows them by. */
  protected readonly recordTypes = [
    ['Appointment', 'Appointments'],
    ['Order', 'Orders'],
    ['Payment', 'Payments'],
    ['Deposit', 'Deposits'],
    ['GiftCard', 'Gift cards'],
    ['Membership', 'Memberships'],
    ['Client', 'Clients'],
    ['StaffProfile', 'Staff'],
    ['EarningLine', 'Earnings'],
    ['StaffRequest', 'Staff requests'],
  ];

  protected readonly list = new ListState<AuditFilters>(
    this.router,
    this.route,
    { sort: 'occurred', dir: 'desc', limit: 50, filters: { auditable_type: '', from: '', to: '' } },
    () => this.reload(),
  );

  ngOnInit(): void {
    this.list.readFromUrl();
    this.reload();
  }

  protected reload(): void {
    this.request?.unsubscribe();
    this.loading.set(true);
    this.error.set(null);
    const q = this.list.query();
    this.request = this.api
      .auditLogs({
        action: q.q,
        auditable_type: this.list.filters().auditable_type,
        from: this.list.filters().from,
        to: this.list.filters().to,
        page: q.page,
        limit: q.limit,
      })
      .subscribe({
        next: ({ audit_logs, meta }) => {
          this.logs.set(audit_logs);
          this.meta.set(meta);
          this.loading.set(false);
        },
        error: () => {
          this.error.set('Could not load the audit log.');
          this.loading.set(false);
        },
      });
  }

  /** "GiftCard" reads as "Gift card". */
  protected recordLabel(type: string): string {
    return humanise(type.replace(/([a-z])([A-Z])/g, '$1_$2').toLowerCase());
  }

  /** "gift_card.issued" reads as "Gift card issued". */
  protected actionLabel(action: string): string {
    return humanise(action.replace(/\./g, ' '));
  }

  /** The role only when it adds something — "Owner / owner" says nothing twice. */
  protected roleLabel(log: AuditLogRecord): string {
    const role = log.actor?.role;
    if (!role || log.actor?.name.toLowerCase() === role) return '';
    return humanise(role);
  }

  /** `{ amount_cents: 1000, phone: ["old", "new"] }` reads as "Amount: $10.00 · Phone: old → new". */
  protected changes(log: AuditLogRecord): string {
    const entries = Object.entries(log.changes ?? {});
    if (!entries.length) return '—';
    return entries
      .map(([key, value]) => `${humanise(key.replace(/_cents$/, ''))}: ${this.value(key, value)}`)
      .join(' · ');
  }

  private value(key: string, value: unknown): string {
    if (Array.isArray(value) && value.length === 2) {
      return `${this.value(key, value[0])} → ${this.value(key, value[1])}`;
    }
    if (key.endsWith('_cents') && typeof value === 'number') return `$${(value / 100).toFixed(2)}`;
    if (value === null || value === undefined || value === '') return '—';
    if (typeof value === 'object') return JSON.stringify(value);
    return String(value);
  }
}
