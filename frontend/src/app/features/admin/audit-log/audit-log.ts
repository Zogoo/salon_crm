import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuditLogRecord, PageMeta } from '../../../core/models';
import { WallClockPipe } from '../../../core/pipes/wall-clock.pipe';
import { MassagelabService } from '../../../core/services/massagelab.service';
import {
  UiBanner,
  UiButton,
  UiCard,
  UiEmpty,
  UiField,
  UiPage,
  UiTable,
  humanise,
} from '../../../ui';

@Component({
  selector: 'app-audit-log',
  imports: [
    FormsModule,
    WallClockPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiTable,
    UiEmpty,
    UiBanner,
  ],
  templateUrl: './audit-log.html',
  styleUrl: '../../../ui/layouts.scss',
})
export class AuditLogPage implements OnInit {
  private readonly api = inject(MassagelabService);

  protected readonly logs = signal<AuditLogRecord[]>([]);
  protected readonly meta = signal<PageMeta | null>(null);
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected filters = { action: '', auditable_type: '', from: '', to: '', page: 1 };

  ngOnInit(): void {
    this.reload();
  }

  protected reload(page = 1): void {
    this.filters.page = page;
    this.loading.set(true);
    this.error.set(null);
    this.api.auditLogs(this.filters).subscribe({
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

  protected readonly humanise = humanise;

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
