import { Injectable, computed, inject, signal } from '@angular/core';

import { Location } from '../models';
import { MassagelabService } from './massagelab.service';

/**
 * The selected location, shown top-left on every screen (FRS §1).
 * The Owner can switch; a Manager is pinned to one and the API enforces it —
 * this only decides what the UI offers.
 */
@Injectable({ providedIn: 'root' })
export class LocationContextService {
  private readonly api = inject(MassagelabService);

  private readonly all = signal<Location[]>([]);
  private readonly selectedId = signal<number | null>(null);

  readonly locations = this.all.asReadonly();
  readonly current = computed(() => this.all().find((l) => l.id === this.selectedId()) ?? null);
  readonly canSwitch = computed(() => this.all().length > 1);

  load(): Promise<void> {
    return new Promise((resolve) => {
      this.api.locations().subscribe({
        next: ({ locations }) => {
          this.all.set(locations);
          if (!this.selectedId() && locations.length) {
            const stored = Number(localStorage.getItem('massagelab_location'));
            const valid = locations.some((l) => l.id === stored);
            this.select(valid ? stored : locations[0].id);
          }
          resolve();
        },
        error: () => resolve(),
      });
    });
  }

  select(id: number): void {
    this.selectedId.set(id);
    localStorage.setItem('massagelab_location', String(id));
  }

  clear(): void {
    this.all.set([]);
    this.selectedId.set(null);
  }
}
