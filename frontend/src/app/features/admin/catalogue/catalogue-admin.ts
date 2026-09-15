import { LocationScope } from '../../../shared/location-scope';
import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { CatalogueService, CatalogueVariant, Service, VariantPrice } from '../../../core/models';
import { LocationContextService } from '../../../core/services/location-context.service';
import { MassagelabService } from '../../../core/services/massagelab.service';
import { todayIn } from '../../../core/salon-date';
import {
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiField,
  UiPage,
  UiTable,
  humanise,
} from '../../../ui';

/**
 * FRS §19 / doc 05 §5 — the service menu and the price list.
 *
 * Prices are per location and effective-dated (invariant 5). Saving one opens
 * a new period rather than editing the old, because BR-11 snapshots the price
 * onto the appointment at booking: changing a price must never reach back into
 * an order already taken.
 */
@Component({
  selector: 'app-catalogue-admin',
  imports: [
    FormsModule,
    DecimalPipe,
    UiPage,
    LocationScope,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiTable,
    UiBanner,
  ],
  templateUrl: './catalogue-admin.html',
  styleUrl: '../../../ui/layouts.scss',
})
export class CatalogueAdminPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly services = signal<Service[]>([]);
  protected readonly detail = signal<CatalogueService | null>(null);
  protected readonly prices = signal<VariantPrice[]>([]);
  protected readonly pricedVariant = signal<CatalogueVariant | null>(null);
  protected readonly categories = signal<{ id: number; name: string }[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);

  /** The lengths therapist pay is defined for (FRS §4). */
  protected readonly ladder = [30, 45, 60, 75, 90, 120];

  protected humanStatus(value: string) {
    return humanise(value);
  }

  protected creating = false;
  protected editingService = false;
  protected editingVariantId: number | null = null;
  protected newService = { name: '', kind: 'standard', service_category_id: 0 };
  protected serviceForm = { name: '', kind: 'standard', service_category_id: 0 };
  protected newVariant = { duration_minutes: 60, therapist_count: 1, required_client_capacity: 1 };
  protected variantForm = {
    duration_minutes: 60,
    therapist_count: 1,
    required_client_capacity: 1,
    requires_room_type: null as string | null,
    active: true,
  };
  protected priceForm = { dollars: 0, effective_from: '' };

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.priceForm.effective_from = todayIn(this.ctx.current()?.timezone);
      this.reload();
      this.api.catalogue().subscribe({
        next: ({ service_categories }) => {
          this.categories.set(service_categories);
          this.newService.service_category_id = service_categories[0]?.id ?? 0;
        },
        error: () => this.categories.set([]),
      });
    });
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    this.reload();
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.services(loc.id).subscribe({
      next: ({ services }) => this.services.set(services),
      error: (err) => this.error.set(this.message(err, 'Could not load the menu')),
    });
  }

  protected open(service: { id: number }): void {
    this.clear();
    this.prices.set([]);
    this.pricedVariant.set(null);
    this.api.catalogueService(service.id).subscribe({
      next: (full) => {
        this.detail.set(full);
        this.editingService = false;
        this.editingVariantId = null;
        this.serviceForm = {
          name: full.name,
          kind: full.kind,
          service_category_id: full.service_category_id,
        };
      },
      error: (err) => this.error.set(this.message(err, 'Could not load that service')),
    });
  }

  protected createService(): void {
    this.clear();
    this.api.createService(this.newService).subscribe({
      next: (created) => {
        this.creating = false;
        this.detail.set(created);
        this.notice.set(`${created.name} added. Give it at least one duration below.`);
        this.newService.name = '';
        this.reload();
      },
      error: (err) => this.error.set(this.message(err, 'Could not add that service')),
    });
  }

  protected toggleActive(service: CatalogueService): void {
    this.clear();
    this.api.setServiceActive(service.id, !service.active).subscribe({
      next: (updated) => {
        this.detail.set(updated);
        this.notice.set(
          updated.active ? 'Back on the menu.' : 'Off the menu; history is untouched.',
        );
        this.reload();
      },
      error: (err) => this.error.set(this.message(err, 'Could not change that')),
    });
  }

  protected saveService(service: CatalogueService): void {
    this.clear();
    this.api.updateService(service.id, this.serviceForm).subscribe({
      next: (updated) => {
        this.detail.set(updated);
        this.editingService = false;
        this.notice.set('Service details saved. Existing appointments keep their snapshots.');
        this.reload();
      },
      error: (err) => this.error.set(this.message(err, 'Could not save that service')),
    });
  }

  protected deleteService(service: CatalogueService): void {
    this.api.deleteService(service.id).subscribe({
      next: () => {
        this.detail.set(null);
        this.notice.set('Unused service deleted.');
        this.reload();
      },
      error: (err) => this.error.set(this.message(err, 'Could not delete that service')),
    });
  }

  protected editVariant(variant: CatalogueVariant): void {
    this.editingVariantId = variant.id;
    this.variantForm = {
      duration_minutes: variant.duration_minutes,
      therapist_count: variant.therapist_count,
      required_client_capacity: variant.required_client_capacity,
      requires_room_type: variant.requires_room_type,
      active: variant.active,
    };
  }

  protected saveVariant(service: CatalogueService, variant: CatalogueVariant): void {
    this.clear();
    this.api.updateVariant(variant.id, this.variantForm).subscribe({
      next: () => {
        this.editingVariantId = null;
        this.notice.set('Session length saved. Past appointments are unchanged.');
        this.open(service);
      },
      error: (err) => this.error.set(this.message(err, 'Could not save that session length')),
    });
  }

  protected addVariant(): void {
    const service = this.detail();
    if (!service) return;
    this.clear();

    this.api.createVariant(service.id, this.newVariant).subscribe({
      next: () => {
        this.notice.set('Duration added. Set a price for it before it can be booked.');
        this.open(service);
      },
      // A duration off the pay ladder is refused: it would produce an
      // unpayable earning line (BR-33).
      error: (err) =>
        this.error.set(
          this.message(
            err,
            'Could not add that duration — it must sit on the pay ladder (30/45/60/75/90/120).',
          ),
        ),
    });
  }

  protected showPrices(variant: CatalogueVariant): void {
    this.clear();
    this.pricedVariant.set(variant);
    this.api.variantPrices(variant.id).subscribe({
      next: ({ prices }) => this.prices.set(prices),
      error: (err) => this.error.set(this.message(err, 'Could not load prices')),
    });
  }

  protected savePrice(): void {
    const variant = this.pricedVariant();
    const loc = this.ctx.current();
    if (!variant || !loc) return;
    this.clear();

    this.api
      .setVariantPrice(
        variant.id,
        loc.id,
        Math.round(this.priceForm.dollars * 100),
        this.priceForm.effective_from,
      )
      .subscribe({
        next: () => {
          this.notice.set(
            `New price applies from ${this.priceForm.effective_from}. Orders already taken keep the price they were sold at.`,
          );
          this.showPrices(variant);
        },
        error: (err) => this.error.set(this.message(err, 'Could not set that price')),
      });
  }

  protected currentPrices(): VariantPrice[] {
    return this.prices().filter((p) => !p.effective_to);
  }

  protected pastPrices(): VariantPrice[] {
    return this.prices().filter((p) => p.effective_to);
  }

  private clear(): void {
    this.error.set(null);
    this.notice.set(null);
  }

  private message(err: unknown, fallback: string): string {
    const e = err as { error?: { error?: { message?: string; code?: string } | string } };
    const body = e?.error?.error;
    if (typeof body === 'string') return body;
    return body?.message ?? body?.code ?? fallback;
  }
}
