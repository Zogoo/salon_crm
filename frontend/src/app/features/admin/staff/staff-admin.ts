import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import {
  MonthlyRate,
  Qualification,
  Service,
  SessionRate,
  StaffMember,
} from '../../../core/models';
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
  statusTone,
} from '../../../ui';
import { LocationContextService } from '../../../core/services/location-context.service';
import { MassagelabService } from '../../../core/services/massagelab.service';
import { todayIn } from '../../../core/salon-date';

/** The six rungs a therapist is paid on (FRS §4). */
const LADDER = [30, 45, 60, 75, 90, 120] as const;

/**
 * Doc 01 §3.1 / doc 05 §6 — the Owner's staff administration.
 *
 * Rates are the reason this screen is Owner-only. They are effective-dated
 * (BR-35): saving a ladder never edits the one in force, it opens a new period
 * from a date you choose, so pay already earned cannot be restated.
 */
@Component({
  selector: 'app-staff-admin',
  imports: [
    FormsModule,
    DecimalPipe,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiTable,
    UiBanner,
  ],
  templateUrl: './staff-admin.html',
  styleUrl: '../../../ui/layouts.scss',
})
export class StaffAdminPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly staff = signal<StaffMember[]>([]);
  protected readonly selected = signal<StaffMember | null>(null);
  protected readonly quals = signal<Qualification[]>([]);
  protected readonly rates = signal<SessionRate[]>([]);
  protected readonly monthlyRates = signal<MonthlyRate[]>([]);
  protected readonly services = signal<Service[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly showOffboarded = signal(false);

  protected readonly ladder = LADDER;

  protected tone(status: string) {
    return statusTone(status);
  }
  protected humanStatus(status: string) {
    return humanise(status);
  }

  protected memberSummary(member: StaffMember): string {
    const paid = member.engagement_type === 'manager_flat' ? 'flat monthly' : 'per session';
    return `${member.email ?? ''} · paid ${paid} · hired ${member.hire_date ?? '—'}`;
  }

  // The ladder being edited, in dollars — cents are an API detail.
  protected rateForm: Record<number, number> = {};
  protected rateEffectiveFrom = '';
  protected rateNote = '';
  protected staffForm = {
    display_name: '',
    email: '',
    employee_code: '',
    hire_date: '',
    can_edit_service_menu: false,
  };
  protected monthlyForm = { dollars: 0, effective_from: '', note: '' };

  protected creating = false;
  protected newStaff = {
    display_name: '',
    email: '',
    role: 'staff',
    engagement_type: 'contractor_1099',
    employee_code: '',
  };

  protected readonly isManagerEngagement = computed(
    () => this.selected()?.engagement_type === 'manager_flat',
  );

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.rateEffectiveFrom = todayIn(this.ctx.current()?.timezone);
      this.monthlyForm.effective_from = this.rateEffectiveFrom;
      // Seed before anyone is selected: onboarding writes this same ladder,
      // and an unseeded form would silently create a therapist on zero pay.
      this.seedRateForm([]);
      this.reload();
      this.loadServices();
    });
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.staff(loc.id, this.showOffboarded() ? 'all' : 'active').subscribe({
      next: ({ staff }) => this.staff.set(staff),
      error: (err) => this.error.set(this.message(err, 'Could not load staff')),
    });
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    this.selected.set(null);
    this.reload();
    this.loadServices();
  }

  protected toggleOffboarded(): void {
    this.showOffboarded.update((v) => !v);
    this.reload();
  }

  protected select(member: StaffMember): void {
    this.error.set(null);
    this.notice.set(null);
    this.api.staffMember(member.id).subscribe({
      next: (full) => {
        this.selected.set(full);
        this.seedRateForm(full.session_rates ?? []);
        this.staffForm = {
          display_name: full.display_name,
          email: full.email ?? '',
          employee_code: full.employee_code,
          hire_date: full.hire_date ?? '',
          can_edit_service_menu: full.can_edit_service_menu ?? false,
        };
        if (full.engagement_type === 'manager_flat') this.loadMonthlyRate(full.id);
      },
      error: (err) => this.error.set(this.message(err, 'Could not load that therapist')),
    });
    this.api.qualifications(member.id).subscribe({
      next: ({ qualifications }) => this.quals.set(qualifications),
      error: () => this.quals.set([]),
    });
    this.api.sessionRates(member.id).subscribe({
      next: ({ session_rates }) => this.rates.set(session_rates),
      // A Manager is never given rates at all, so an error here is expected.
      error: () => this.rates.set([]),
    });
  }

  protected saveStaff(member: StaffMember): void {
    this.api.updateStaff(member.id, this.staffForm).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.notice.set('Staff profile saved.');
        this.reload();
      },
      error: (err) => this.error.set(this.message(err, 'Could not save the staff profile')),
    });
  }

  protected saveMonthlyRate(member: StaffMember): void {
    this.api
      .setMonthlyRate(
        member.id,
        Math.round(this.monthlyForm.dollars * 100),
        this.monthlyForm.effective_from,
        this.monthlyForm.note,
      )
      .subscribe({
        next: ({ monthly_rates }) => {
          this.monthlyRates.set(monthly_rates);
          this.monthlyForm.note = '';
          this.notice.set('Monthly rate saved. Earlier periods are unchanged.');
        },
        error: (err) => this.error.set(this.message(err, 'Could not save the monthly rate')),
      });
  }

  // --- onboarding ---

  protected create(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.error.set(null);

    const manager = this.newStaff.engagement_type === 'manager_flat';
    // BR-36: a manager earns no session rates, so sending a ladder for one
    // would be meaningless rather than merely unused.
    if (!manager && this.ladderPayload().every((r) => r.rate_cents === 0)) {
      this.error.set(
        'Set the pay ladder before adding a therapist — a ladder of zeros is not a rate.',
      );
      return;
    }

    this.api
      .createStaff({
        ...this.newStaff,
        location_id: loc.id,
        service_ids: this.services().map((s) => s.id),
        session_rates: manager ? undefined : this.ladderPayload(),
        rates_effective_from: this.rateEffectiveFrom,
      })
      .subscribe({
        next: (created) => {
          this.creating = false;
          this.notice.set(`${created.display_name} added.`);
          this.newStaff = {
            display_name: '',
            email: '',
            role: 'staff',
            engagement_type: 'contractor_1099',
            employee_code: '',
          };
          this.reload();
        },
        error: (err) => this.error.set(this.message(err, 'Could not add that therapist')),
      });
  }

  protected offboard(member: StaffMember): void {
    this.error.set(null);
    this.api.offboardStaff(member.id).subscribe({
      next: () => {
        this.notice.set(`${member.display_name} offboarded.`);
        this.selected.set(null);
        this.reload();
      },
      error: (err) => {
        // BR-02: blocked, with the appointments that are in the way.
        const ids = err?.error?.error?.details?.appointment_ids as number[] | undefined;
        this.error.set(
          ids?.length
            ? `Still has booked appointments (${ids.join(', ')}). Reassign or cancel them first.`
            : this.message(err, 'Could not offboard'),
        );
      },
    });
  }

  // --- qualifications (BR-01) ---

  protected qualified(serviceId: number): boolean {
    return this.quals().some((q) => q.service_id === serviceId);
  }

  protected toggleQualification(serviceId: number, on: boolean): void {
    const member = this.selected();
    if (!member) return;

    const next = on
      ? [...this.quals().map((q) => q.service_id), serviceId]
      : this.quals()
          .map((q) => q.service_id)
          .filter((id) => id !== serviceId);

    this.api.setQualifications(member.id, next).subscribe({
      next: ({ qualifications }) => {
        this.quals.set(qualifications);
        this.notice.set('Qualifications saved.');
      },
      // The API refuses to leave a therapist with none, because they would
      // silently vanish from every availability search.
      error: (err) => this.error.set(this.message(err, 'Could not save qualifications')),
    });
  }

  // --- rates (BR-35) ---

  protected saveRates(): void {
    const member = this.selected();
    if (!member) return;
    this.error.set(null);

    this.api
      .setSessionRates(member.id, this.ladderPayload(), this.rateEffectiveFrom, this.rateNote)
      .subscribe({
        next: ({ session_rates }) => {
          this.rates.set(session_rates);
          this.rateNote = '';
          this.notice.set(
            `New rates take effect ${this.rateEffectiveFrom}. Earlier pay is unchanged.`,
          );
        },
        error: (err) => this.error.set(this.message(err, 'Could not save rates')),
      });
  }

  protected currentRates(): SessionRate[] {
    return this.rates().filter((r) => !r.effective_to);
  }

  protected pastRates(): SessionRate[] {
    return this.rates().filter((r) => r.effective_to);
  }

  private ladderPayload(): { duration_minutes: number; rate_cents: number }[] {
    return LADDER.map((d) => ({
      duration_minutes: d,
      rate_cents: Math.round((this.rateForm[d] ?? 0) * 100),
    }));
  }

  private seedRateForm(rates: SessionRate[]): void {
    const form: Record<number, number> = {};
    for (const d of LADDER) {
      const open = rates.find((r) => r.duration_minutes === d && !r.effective_to);
      form[d] = open ? open.rate_cents / 100 : 0;
    }
    this.rateForm = form;
  }

  private loadServices(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.services(loc.id).subscribe({
      next: ({ services }) => this.services.set(services),
      error: () => this.services.set([]),
    });
  }

  private loadMonthlyRate(id: number): void {
    this.api.monthlyRate(id).subscribe({
      next: ({ monthly_rates }) => {
        this.monthlyRates.set(monthly_rates);
        const current = monthly_rates.find((rate) => !rate.effective_to);
        this.monthlyForm.dollars = (current?.amount_cents ?? 0) / 100;
      },
      error: () => this.monthlyRates.set([]),
    });
  }

  private message(err: unknown, fallback: string): string {
    const e = err as { error?: { error?: { message?: string; code?: string } | string } };
    const body = e?.error?.error;
    if (typeof body === 'string') return body;
    return body?.message ?? body?.code ?? fallback;
  }
}
