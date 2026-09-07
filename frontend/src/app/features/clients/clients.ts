import { Component, OnInit, inject, signal } from '@angular/core';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { FormsModule } from '@angular/forms';

import { ClientRecord } from '../../core/models';
import { MassagelabService } from '../../core/services/massagelab.service';

/** FRS §11 — client profiles and the preferences form (§11.1). */
@Component({
  selector: 'app-clients',
  imports: [FormsModule, WallClockPipe],
  templateUrl: './clients.html',
  styles: [
    `
      .clients { display: grid; grid-template-columns: minmax(16rem, 22rem) 1fr; gap: 1rem; align-items: start; }
      @media (max-width: 720px) { .clients { grid-template-columns: 1fr; } }
      .panel { border: 1px solid var(--border, #e2e4e9); border-radius: .6rem; padding: .9rem; background: #fff; display: flex; flex-direction: column; gap: .6rem; }
      h1 { font-size: 1.15rem; margin: 0; }
      h2 { font-size: 1rem; margin: 0; }
      h3 { font-size: .78rem; text-transform: uppercase; letter-spacing: .04em; color: #6b7280; margin: .4rem 0 0; }
      input, select, textarea { font: inherit; padding: .4rem .5rem; border: 1px solid var(--border, #e2e4e9); border-radius: .4rem; width: 100%; box-sizing: border-box; }
      .list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: .25rem; max-height: 26rem; overflow-y: auto; }
      .list button { width: 100%; text-align: left; border: 1px solid transparent; background: transparent; padding: .45rem .5rem; border-radius: .4rem; cursor: pointer; }
      .list button:hover { background: #f4f6f9; }
      .list button.on { background: #e8f0fe; border-color: #c6d8f7; }
      .muted { color: #6b7280; font-size: .85rem; }
      .warn { color: #9a3412; font-weight: 600; }
      .field { display: flex; flex-direction: column; gap: .25rem; font-size: .85rem; }
      .visits { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: .3rem; font-size: .85rem; }
      .visits li { display: flex; gap: .5rem; }
      .btn { border: 1px solid transparent; background: #1f6feb; color: #fff; padding: .45rem .8rem; border-radius: .4rem; cursor: pointer; font-size: .88rem; }
      .ok { color: #15803d; font-size: .85rem; }
    `,
  ],
})
export class ClientsPage implements OnInit {
  private readonly api = inject(MassagelabService);

  protected readonly clients = signal<ClientRecord[]>([]);
  protected readonly selected = signal<ClientRecord | null>(null);
  protected readonly saved = signal(false);
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
