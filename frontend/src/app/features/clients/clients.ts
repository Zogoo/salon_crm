import { Component, OnInit, inject, signal } from '@angular/core';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { FormsModule } from '@angular/forms';

import { ClientRecord } from '../../core/models';
import { MassagelabService } from '../../core/services/massagelab.service';
import {
  Fact,
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiFacts,
  UiField,
  UiPage,
  UiTable,
  humanise,
  statusTone,
} from '../../ui';

/** FRS §11 — client profiles and the preferences form (§11.1). */
@Component({
  selector: 'app-clients',
  imports: [
    FormsModule,
    WallClockPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiTable,
    UiFacts,
    UiBanner,
  ],
  templateUrl: './clients.html',
  styleUrl: './clients.scss',
})
export class ClientsPage implements OnInit {
  private readonly api = inject(MassagelabService);

  protected readonly clients = signal<ClientRecord[]>([]);
  protected readonly selected = signal<ClientRecord | null>(null);
  protected readonly saved = signal(false);

  protected tone(status: string) { return statusTone(status); }
  protected humanStatus(status: string) { return humanise(status); }

  protected contact(client: ClientRecord): string {
    return [client.phone, client.email].filter(Boolean).join(' · ');
  }

  /**
   * BR-20 counters. Shown as plain counts with no judgement attached — the
   * desk decides what to do with them.
   */
  protected reliability(client: ClientRecord): Fact[] {
    return [
      { label: 'No-shows', value: client.no_show_count ?? 0 },
      { label: 'Late cancellations', value: client.late_cancel_count ?? 0 },
      { label: 'Visits recorded', value: client.appointments?.length ?? 0 },
    ];
  }
  protected search = '';
  protected pref = { attention_areas: '', avoid_areas: '', pressure: '', other_requests: '' };

  ngOnInit(): void {
    this.reload();
  }

  protected reload(): void {
    this.api.clients(this.search).subscribe(({ clients }) => this.clients.set(clients));
  }

  protected open(client: ClientRecord): void {
    this.saved.set(false);
    this.api.client(client.id).subscribe((full) => {
      this.selected.set(full);
      this.pref = {
        attention_areas: full.preference?.attention_areas ?? '',
        avoid_areas: full.preference?.avoid_areas ?? '',
        pressure: full.preference?.pressure ?? '',
        other_requests: full.preference?.other_requests ?? '',
      };
    });
  }

  protected savePreferences(): void {
    const client = this.selected();
    if (!client) return;
    this.api.savePreferences(client.id, this.pref).subscribe((updated) => {
      this.selected.set(updated);
      this.saved.set(true);
    });
  }
}
