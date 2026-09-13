import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { ClientRecord, MembershipRecord, PaymentMethod, Service } from '../../core/models';
import { LocationContextService } from '../../core/services/location-context.service';
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
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';

/**
 * FRS §23 — $80/month, one 60-minute massage, rollover capped at 3, 15 days'
 * notice to cancel, tied to the joining location.
 *
 * Release 1 bills by hand: recording the monthly payment is what grants the
 * credit. Release 2 replaces that with a Stripe subscription; the entitlement
 * rules below are identical either way.
 */
@Component({
  selector: 'app-membership',
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
    UiTable,
    UiFacts,
    UiBanner,
  ],
  templateUrl: './membership.html',
  styleUrl: '../../ui/layouts.scss',
})
export class MembershipPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly memberships = signal<MembershipRecord[]>([]);
  protected readonly selected = signal<MembershipRecord | null>(null);
  protected readonly clients = signal<ClientRecord[]>([]);
  protected readonly included = signal<{ id: number; label: string }[]>([]);
  protected readonly error = signal<string | null>(null);

  protected newClientId: number | null = null;
  protected newVariantId: number | null = null;
  protected readonly methods: PaymentMethod[] = ['card', 'cash', 'zelle', 'online', 'other'];
  protected tone(status: string) {
    return statusTone(status);
  }
  protected humanStatus(value: string) {
    return humanise(value);
  }

  protected memberFacts(m: MembershipRecord): Fact[] {
    return [
      { label: 'Credits', value: `${m.credits_balance} / ${m.credits_cap}` },
      { label: 'Renews', value: m.current_period_end?.slice(0, 10) },
      { label: 'Status', value: humanise(m.status) },
    ];
  }

  protected payMethod: PaymentMethod = 'card';

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.reload();
      this.api.clients().subscribe(({ clients }) => this.clients.set(clients));
      this.loadIncludedOptions();
    });
  }

  protected reload(): void {
    this.api.memberships().subscribe(({ memberships }) => this.memberships.set(memberships));
  }

  // FRS §23: the member picks deep tissue, Swedish or sport as the included
  // 60-minute massage.
  private loadIncludedOptions(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.services(loc.id).subscribe(({ services }) => {
      const options: { id: number; label: string }[] = [];
      services
        .filter((s: Service) => s.kind === 'standard' && s.category === 'massage')
        .forEach((s) =>
          s.variants
            .filter((v) => v.duration_minutes === 60 && v.therapist_count === 1)
            .forEach((v) => options.push({ id: v.id, label: `${s.name} (60 min)` })),
        );
      this.included.set(options);
      this.newVariantId ??= options[0]?.id ?? null;
    });
  }

  protected open(m: MembershipRecord): void {
    this.api.membership(m.id).subscribe((full) => this.selected.set(full));
  }

  protected enrol(): void {
    const loc = this.ctx.current();
    if (!loc || !this.newClientId) return;
    this.error.set(null);
    this.api
      .enrolMembership({
        client_id: this.newClientId,
        location_id: loc.id,
        default_service_variant_id: this.newVariantId,
      })
      .subscribe({
        next: (m) => {
          this.selected.set(m);
          this.reload();
        },
        error: (err) => this.error.set(this.message(err)),
      });
  }

  protected recordPayment(m: MembershipRecord): void {
    this.error.set(null);
    this.api.recordMembershipPayment(m.id, this.payMethod).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.reload();
      },
      error: (err) => this.error.set(this.message(err)),
    });
  }

  protected cancel(m: MembershipRecord): void {
    this.api.cancelMembership(m.id).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.reload();
      },
      error: (err) => this.error.set(this.message(err)),
    });
  }

  private message(err: unknown): string {
    const code = (err as { error?: { error?: { code?: string } } })?.error?.error?.code;
    const map: Record<string, string> = {
      already_a_member: 'That client already has a membership.',
      cycle_already_charged: 'This cycle has already been paid.',
      credit_cap_reached: 'Credits are capped at three.',
    };
    return code ? (map[code] ?? code) : 'Something went wrong';
  }
}
