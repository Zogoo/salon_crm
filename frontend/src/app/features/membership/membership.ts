import { PhonePipe, formatPhone } from '../../core/phone';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { ListState } from '../../core/list-state';
import {
  ClientRecord,
  MembershipRecord,
  PageMeta,
  PaymentMethod,
  Service,
} from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { ClientPicker } from '../../shared/client-picker';
import {
  ConfirmService,
  Fact,
  UiBanner,
  UiButton,
  UiChip,
  UiDialog,
  UiEmpty,
  UiFacts,
  UiField,
  UiIcon,
  UiPage,
  UiPaginator,
  UiSheet,
  humanise,
} from '../../ui';

type MemberFilters = { status: string; at_cap: string; location_id: string };

const STATUS_LABEL: Record<string, string> = {
  active: 'Active',
  pending_cancellation: 'Cancelling',
  cancelled: 'Cancelled',
  past_due: 'Payment overdue',
};

/**
 * FRS §23 — $80/month, one 60-minute massage, rollover capped at 3, 15 days'
 * notice to cancel, tied to the joining location. Hundreds of members, so the
 * list is searched and paged on the server and a member opens in a side panel.
 *
 * Release 1 bills by hand: recording the monthly payment is what grants the
 * credit.
 */
@Component({
  selector: 'app-membership',
  imports: [
    PhonePipe,
    FormsModule,
    DecimalPipe,
    WallClockPipe,
    UiPage,
    UiButton,
    UiIcon,
    UiChip,
    UiEmpty,
    UiFacts,
    UiField,
    UiBanner,
    UiDialog,
    UiSheet,
    UiPaginator,
    ClientPicker,
  ],
  templateUrl: './membership.html',
  styleUrls: ['../../ui/layouts.scss', '../../ui/data-table.scss', './membership.scss'],
})
export class MembershipPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly auth = inject(AuthService);
  private readonly confirm = inject(ConfirmService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  protected readonly ctx = inject(LocationContextService);

  protected readonly rows = signal<MembershipRecord[]>([]);
  protected readonly meta = signal<PageMeta | null>(null);
  protected readonly loading = signal(true);
  protected readonly selected = signal<MembershipRecord | null>(null);
  protected readonly included = signal<{ id: number; label: string }[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly enrolling = signal(false);
  protected readonly enrolClient = signal<ClientRecord | null>(null);
  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');
  protected readonly skeleton = Array.from({ length: 6 });

  protected readonly methods: PaymentMethod[] = ['card', 'cash', 'zelle', 'online', 'other'];
  protected newVariantId: number | null = null;
  protected payMethod: PaymentMethod = 'card';
  protected editVariantId: number | null = null;
  private request?: Subscription;

  protected readonly list = new ListState<MemberFilters>(
    this.router,
    this.route,
    { sort: 'client', dir: 'asc', filters: { status: 'current', at_cap: '', location_id: '' } },
    () => this.reload(),
  );

  protected readonly summary = computed(() => {
    const f = this.list.filters();
    const parts: string[] = [];
    if (f.status === '') parts.push('every status');
    else if (f.status !== 'current') parts.push(STATUS_LABEL[f.status]?.toLowerCase() ?? f.status);
    if (f.at_cap === 'true') parts.push('at the credit cap');
    if (f.location_id) {
      parts.push(
        `joined at ${this.ctx.locations().find((l) => String(l.id) === f.location_id)?.name ?? 'one location'}`,
      );
    }
    if (this.list.q().trim()) parts.push(`matching “${this.list.q().trim()}”`);
    return parts.join(' · ');
  });

  protected humanStatus = humanise;

  ngOnInit(): void {
    this.list.readFromUrl();
    void this.ctx.load().then(() => {
      this.reload();
      this.loadIncludedOptions();
    });
  }

  protected statusLabel(status: string): string {
    return STATUS_LABEL[status] ?? humanise(status);
  }

  protected statusTone(status: string): 'success' | 'warning' | 'neutral' | 'error' {
    return status === 'active'
      ? 'success'
      : status === 'cancelled'
        ? 'neutral'
        : status === 'past_due'
          ? 'error'
          : 'warning';
  }

  protected memberFacts(m: MembershipRecord): Fact[] {
    return [
      {
        label: 'Credits',
        value: `${m.credits_balance} of ${m.credits_cap}`,
        hint: 'One massage each; rolls over up to three.',
      },
      { label: 'Renews', value: m.current_period_end?.slice(0, 10) },
      {
        label: 'Home location',
        value: m.location.name,
        hint: 'Using it elsewhere needs an override.',
      },
      { label: 'Member since', value: m.enrolled_at?.slice(0, 10) ?? '—' },
      { label: 'Phone', value: formatPhone(m.client.phone) || '—' },
    ];
  }

  protected toggleAtCap(): void {
    this.list.setFilter('at_cap', this.list.filters().at_cap === 'true' ? '' : 'true');
  }

  protected reload(): void {
    this.request?.unsubscribe();
    this.loading.set(true);
    this.request = this.api.membershipList(this.list.query()).subscribe({
      next: ({ memberships, meta }) => {
        this.rows.set(memberships);
        this.meta.set(meta);
        this.loading.set(false);
      },
      error: () => {
        this.error.set('Could not load memberships. Check the connection and try again.');
        this.loading.set(false);
      },
    });
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
    this.api.membership(m.id).subscribe({
      next: (full) => {
        this.selected.set(full);
        this.editVariantId = full.default_service_variant_id ?? null;
      },
      error: () => this.error.set('Could not open that membership.'),
    });
  }

  protected openEnrol(): void {
    this.enrolClient.set(null);
    this.error.set(null);
    this.enrolling.set(true);
  }

  protected enrol(): void {
    const loc = this.ctx.current();
    const client = this.enrolClient();
    if (!loc || !client) return;
    this.api
      .enrolMembership({
        client_id: client.id,
        location_id: loc.id,
        default_service_variant_id: this.newVariantId,
      })
      .subscribe({
        next: (m) => {
          this.enrolling.set(false);
          this.notice.set(
            `${client.full_name} is now a member. Record their first payment to grant the first credit.`,
          );
          this.reload();
          this.selected.set(m);
          this.editVariantId = m.default_service_variant_id ?? null;
        },
        error: (err) => this.error.set(this.message(err)),
      });
  }

  protected recordPayment(m: MembershipRecord): void {
    this.error.set(null);
    this.api.recordMembershipPayment(m.id, this.payMethod).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.notice.set(`$80 payment recorded for ${m.client.full_name}.`);
        this.reload();
      },
      error: (err) => this.error.set(this.message(err)),
    });
  }

  protected async cancel(m: MembershipRecord): Promise<void> {
    const ok = await this.confirm.confirm({
      title: `Request cancellation for ${m.client.full_name}?`,
      message:
        'Notice is 15 days before renewal. Given later than that, one more monthly charge still happens and the membership ends after the following renewal. Unused credits stay usable until it ends.',
      confirmLabel: 'Request cancellation',
      tone: 'danger',
    });
    if (!ok) return;
    this.api.cancelMembership(m.id).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.notice.set('Cancellation requested.');
        this.reload();
      },
      error: (err) => this.error.set(this.message(err)),
    });
  }

  protected updateIncluded(m: MembershipRecord): void {
    if (!this.editVariantId) return;
    this.api.updateMembership(m.id, this.editVariantId).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.notice.set('Included massage changed.');
      },
      error: (err) => this.error.set(this.message(err)),
    });
  }

  protected async adjustCredits(m: MembershipRecord): Promise<void> {
    const { confirmed, values } = await this.confirm.ask({
      title: `Correct ${m.client.full_name}'s credits`,
      message: `Currently ${m.credits_balance} of ${m.credits_cap}. The change and reason stay in the credit ledger with your name.`,
      confirmLabel: 'Apply correction',
      fields: [
        {
          key: 'amount',
          label: 'Change',
          required: true,
          placeholder: 'e.g. 1 or -1',
          hint: 'Use a minus sign to remove credit.',
        },
        { key: 'reason', label: 'Reason', required: true },
      ],
    });
    if (!confirmed) return;
    const amount = Math.trunc(Number(values['amount']));
    if (!Number.isFinite(amount) || amount === 0) {
      this.error.set('Enter a whole number of credits other than zero, like 1 or -1.');
      return;
    }
    this.api.adjustMembershipCredits(m.id, amount, values['reason']).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.notice.set('Credits corrected.');
        this.reload();
      },
      error: (err) => this.error.set(this.message(err)),
    });
  }

  private message(err: unknown): string {
    const code = (err as { error?: { error?: { code?: string } } })?.error?.error?.code;
    const map: Record<string, string> = {
      already_a_member: 'That client already has a membership.',
      cycle_already_charged: 'This month has already been paid.',
      credit_cap_reached: 'Credits must stay between 0 and 3.',
    };
    return code ? (map[code] ?? code) : 'Something went wrong. Please try again.';
  }
}
