import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { ClientRecord, Service, ServiceVariant, Slot, StaffMember } from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
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
} from '../../ui';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';

/** FRS §5 — the New Appointment screen. */
@Component({
  selector: 'app-booking',
  imports: [
    FormsModule,
    DecimalPipe,
    WallClockPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiFacts,
    UiBanner,
  ],
  templateUrl: './booking.html',
  // Shared list-and-detail layout first, then what is specific here.
  styleUrls: ['../../ui/layouts.scss', './booking.scss'],
})
export class BookingPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  protected readonly ctx = inject(LocationContextService);

  protected readonly services = signal<Service[]>([]);
  protected readonly staff = signal<StaffMember[]>([]);
  protected readonly clients = signal<ClientRecord[]>([]);
  protected readonly slots = signal<Slot[]>([]);
  /** Distinguishes "not searched yet" from "searched and found nothing". */
  protected readonly searched = signal(false);
  protected readonly searching = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly suggestions = signal<string[]>([]);
  protected readonly booked = signal<{ reference: string; status: string } | null>(null);

  protected date = '';
  protected clientSearch = '';
  protected selectedClientId: number | null = null;
  // Signals, not plain fields: the computed()s below derive from them, and a
  // computed only recomputes when a signal it read has changed.
  protected readonly selectedVariantId = signal<number | null>(null);
  protected readonly addOnIds = signal<number[]>([]);
  protected readonly enhancementIds = signal<number[]>([]);
  // FRS §5.1: default is no preference — the roster is never the starting point.
  protected requestedStaffId: number | null = null;
  // Feedback 2.1: a couples or four-hands client may ask for both therapists.
  protected secondStaffId: number | null = null;
  protected clientNote = '';
  protected selectedSlot: Slot | null = null;
  protected secondClientId: number | null = null;
  private rebookClientId: number | null = null;
  private rebookVariantId: number | null = null;

  protected showNewClient = false;
  protected newClient = { first_name: '', last_name: '', phone: '', email: '' };

  protected readonly bookable = computed(() =>
    this.services().filter((s) => s.kind === 'standard'),
  );
  protected readonly addOns = computed(() => this.services().filter((s) => s.kind === 'add_on'));
  protected readonly enhancements = computed(() =>
    this.services().filter((s) => s.kind === 'enhancement'),
  );

  protected readonly chosenVariant = computed<ServiceVariant | null>(() => {
    const id = this.selectedVariantId();
    for (const s of this.services()) {
      const v = s.variants.find((x) => x.id === id);
      if (v) return v;
    }
    return null;
  });

  protected readonly needsTwoClients = computed(
    () => (this.chosenVariant()?.required_client_capacity ?? 1) > 1,
  );

  /**
   * What is about to be booked. A summary beats a disabled button: the reader
   * can see the whole decision in one place before committing to it.
   */
  protected summary(): Fact[] {
    const client = this.clients().find((c) => c.id === this.selectedClientId);
    const variant = this.chosenVariant();
    return [
      { label: 'Client', value: client?.full_name },
      { label: 'Service', value: variant ? `${variant.duration_minutes} min` : null },
      { label: 'When', value: this.selectedSlot ? this.selectedSlot.start_at.slice(11, 16) : null },
      { label: 'Date', value: this.date },
      { label: 'Total', value: `$${(this.totalCents() / 100).toFixed(2)}` },
    ];
  }

  /** Names what is missing, so the disabled button is never a mystery. */
  protected blockers(): string[] {
    const missing: string[] = [];
    if (!this.selectedClientId) missing.push('a client');
    if (!this.selectedVariantId()) missing.push('a service');
    if (!this.selectedSlot) missing.push('a time');
    if (this.needsTwoClients() && !this.secondClientId) missing.push('a second client');
    return missing;
  }

  protected useSuggestion(iso: string): void {
    this.date = iso.slice(0, 10);
    this.search();
  }

  protected readonly totalCents = computed(() => {
    const ids = this.variantIds();
    let total = 0;
    for (const s of this.services()) {
      for (const v of s.variants) if (ids.includes(v.id)) total += v.price_cents;
    }
    return total;
  });

  ngOnInit(): void {
    const qDate = this.route.snapshot.queryParamMap.get('date');
    if (qDate) this.date = qDate;
    this.rebookClientId = Number(this.route.snapshot.queryParamMap.get('client_id')) || null;
    this.rebookVariantId = Number(this.route.snapshot.queryParamMap.get('variant_id')) || null;
    void this.ctx.load().then(() => {
      this.date ||= todayIn(this.ctx.current()?.timezone);
      this.loadForLocation();
    });
  }

  protected loadForLocation(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.services(loc.id).subscribe(({ services }) => {
      this.services.set(services);
      if (
        this.rebookVariantId &&
        services.some((service) =>
          service.variants.some((variant) => variant.id === this.rebookVariantId),
        )
      ) {
        this.selectedVariantId.set(this.rebookVariantId);
      }
    });
    this.api.staff(loc.id).subscribe(({ staff }) => this.staff.set(staff));
    this.searchClients();
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    this.reset();
    this.loadForLocation();
  }

  protected searchClients(): void {
    this.api.clients(this.clientSearch).subscribe(({ clients }) => {
      this.clients.set(clients);
      if (this.rebookClientId && clients.some((client) => client.id === this.rebookClientId)) {
        this.selectedClientId = this.rebookClientId;
      }
    });
  }

  protected createClient(): void {
    this.api.createClient(this.newClient).subscribe({
      next: (client) => {
        this.clients.set([client, ...this.clients()]);
        this.selectedClientId = client.id;
        this.showNewClient = false;
        this.newClient = { first_name: '', last_name: '', phone: '', email: '' };
      },
      error: (err) => this.error.set(this.messageFrom(err)),
    });
  }

  protected readonly needsTwoTherapists = computed(
    () => (this.chosenVariant()?.therapist_count ?? 1) > 1,
  );

  protected variantIds(): number[] {
    const ids: number[] = [];
    const chosen = this.selectedVariantId();
    if (chosen) ids.push(chosen);
    return ids.concat(this.addOnIds(), this.enhancementIds());
  }

  protected onVariantChange(id: number | null): void {
    this.selectedVariantId.set(id);
    this.slots.set([]);
    this.selectedSlot = null;
  }

  protected toggle(list: 'addOnIds' | 'enhancementIds', id: number, on: boolean): void {
    const target = list === 'addOnIds' ? this.addOnIds : this.enhancementIds;
    target.update((current) => (on ? [...current, id] : current.filter((x) => x !== id)));
    this.slots.set([]);
    this.selectedSlot = null;
  }

  protected search(): void {
    const loc = this.ctx.current();
    if (!loc || !this.selectedVariantId()) return;
    this.searching.set(true);
    this.error.set(null);
    this.suggestions.set([]);
    this.selectedSlot = null;

    this.api.availability(loc.id, this.variantIds(), this.date, this.requestedStaffId).subscribe({
      next: (res) => {
        this.searched.set(true);
        this.slots.set(res.days[0]?.slots ?? []);
        this.searching.set(false);
      },
      error: (err) => {
        this.error.set(this.messageFrom(err));
        this.searching.set(false);
      },
    });
  }

  protected book(): void {
    const loc = this.ctx.current();
    if (!loc || !this.selectedSlot || !this.selectedClientId) return;
    this.error.set(null);

    const payload: Record<string, unknown> = {
      location_id: loc.id,
      client_id: this.selectedClientId,
      service_variant_ids: this.variantIds(),
      start_at: this.selectedSlot.start_at,
      client_note: this.clientNote || null,
      booking_channel: 'manager',
    };
    if (this.requestedStaffId) payload['requested_staff_profile_id'] = this.requestedStaffId;
    if (this.requestedStaffId && this.needsTwoTherapists() && this.secondStaffId) {
      payload['staff_profile_ids'] = [this.requestedStaffId, this.secondStaffId];
    }
    if (this.needsTwoClients() && this.secondClientId) {
      payload['participant_client_ids'] = [this.secondClientId];
    }

    this.api.book(payload).subscribe({
      next: (appt) => {
        this.booked.set({ reference: appt.reference, status: appt.status });
        this.slots.set([]);
        this.selectedSlot = null;
      },
      error: (err) => {
        this.error.set(this.messageFrom(err));
        // BR-16: the API offers that same therapist's next times, never a substitute.
        this.suggestions.set(err?.error?.error?.details?.suggested_slots ?? []);
        this.search();
      },
    });
  }

  protected goToBoard(): void {
    void this.router.navigate(['/schedule'], { queryParams: { date: this.date } });
  }

  private reset(): void {
    this.selectedVariantId.set(null);
    this.addOnIds.set([]);
    this.enhancementIds.set([]);
    this.requestedStaffId = null;
    this.secondStaffId = null;
    this.slots.set([]);
    this.selectedSlot = null;
    this.booked.set(null);
  }

  private messageFrom(err: unknown): string {
    const e = err as { error?: { error?: unknown } };
    const body = e?.error?.error;
    if (typeof body === 'string') return body;
    if (Array.isArray(body)) return body.join(', ');
    if (body && typeof body === 'object' && 'message' in body) {
      return String((body as { message: unknown }).message);
    }
    return 'Something went wrong';
  }
}
