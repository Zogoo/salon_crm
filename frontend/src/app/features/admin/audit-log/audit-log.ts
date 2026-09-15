import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuditLogRecord, PageMeta } from '../../../core/models';
import { WallClockPipe } from '../../../core/pipes/wall-clock.pipe';
import { MassagelabService } from '../../../core/services/massagelab.service';
import { UiBanner, UiButton, UiCard, UiEmpty, UiField, UiPage, UiTable } from '../../../ui';

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

  protected changes(log: AuditLogRecord): string {
    return Object.keys(log.changes).length ? JSON.stringify(log.changes) : '—';
  }
}
