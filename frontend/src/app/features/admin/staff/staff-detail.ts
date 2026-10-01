import { Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe, Location as BrowserLocation } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  MonthlyRate,
  Qualification,
  Service,
  SessionRate,
  StaffMember,
  WorkingHoursDay,
} from '../../../core/models';
import { AuthService } from '../../../core/services/auth.service';
import { MassagelabService } from '../../../core/services/massagelab.service';
import { todayIn } from '../../../core/salon-date';
import {
  ConfirmService,
  Fact,
  UiBanner,
  UiButton,
  UiCard,
  UiChip,
  UiEmpty,
  UiFacts,
  UiField,
  UiIcon,
  UiPage,
  humanise,
  statusTone,
} from '../../../ui';

/** The six rungs a therapist is paid on (FRS §4). */
export const LADDER = [30, 45, 60, 75, 90, 120] as const;

type Tab = 'profile' | 'hours' | 'qualifications' | 'pay';

type HoursMode = 'unset' | 'working' | 'off';
interface HoursRow {
  weekday: number;
  mode: HoursMode;
  starts_at: string;
  ends_at: string;
}

/** The week as the salon reads it: Monday first. 0 = Sunday, as Date#getDay. */
const WEEK = [1, 2, 3, 4, 5, 6, 0];
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/**
 * One team member. Rates are why this is Owner-only, and they are
 * effective-dated (BR-35): saving never edits the ladder in force, it opens a
 * new period from a chosen date, so pay already earned cannot be restated.
 */
@Component({
  selector: 'app-staff-detail',
  imports: [
    FormsModule,
    RouterLink,
    DecimalPipe,
    UiPage,
    UiCard,
    UiButton,
    UiIcon,
    UiChip,
    UiEmpty,
    UiFacts,
    UiField,
    UiBanner,
  ],
  templateUrl: './staff-detail.html',
  styleUrls: ['../../../ui/layouts.scss', '../../../ui/data-table.scss', './staff.scss'],
})
export class StaffDetailPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly browser = inject(BrowserLocation);
  private readonly confirm = inject(ConfirmService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly auth = inject(AuthService);

  /** A Manager sees the team and sets working hours; profile, qualifications and pay are the Owner's. */
  protected readonly isOwner = computed(() => this.auth.user()?.role === 'owner');
  protected readonly hours = signal<HoursRow[]>(this.emptyWeek());
  protected readonly savingHours = signal(false);

  protected readonly member = signal<StaffMember | null>(null);
  protected readonly selected = this.member;
  protected readonly quals = signal<Qualification[]>([]);
  protected readonly rates = signal<SessionRate[]>([]);
  protected readonly monthlyRates = signal<MonthlyRate[]>([]);
  protected readonly services = signal<Service[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly tab = signal<Tab>('profile');

  protected readonly ladder = LADDER;
  protected rateForm: Record<number, number> = {};
  protected rateEffectiveFrom = '';
  protected rateNote = '';
  protected monthlyForm = { dollars: 0, effective_from: '', note: '' };
  protected staffForm = {
    display_name: '',
    email: '',
    employee_code: '',
    hire_date: '',
    can_edit_service_menu: false,
  };

  protected readonly isManagerEngagement = computed(
    () => this.member()?.engagement_type === 'manager_flat',
  );
  protected readonly currentRates = computed(() => this.rates().filter((r) => !r.effective_to));
  protected readonly pastRates = computed(() => this.rates().filter((r) => r.effective_to));

  protected humanStatus = humanise;
  protected tone = statusTone;

  ngOnInit(): void {
    this.rateEffectiveFrom = todayIn(null);
    this.monthlyForm.effective_from = this.rateEffectiveFrom;
    this.seedRateForm([]);
    this.route.paramMap.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((params) => {
      this.load(Number(params.get('id')));
    });
  }

  protected facts(m: StaffMember): Fact[] {
    return [
      { label: 'Role', value: m.role === 'manager' ? 'Manager' : 'Therapist' },
      { label: 'Location', value: m.location_name ?? '—' },
      { label: 'Employee code', value: m.employee_code },
      {
        label: 'Paid',
        value: m.engagement_type === 'manager_flat' ? 'Flat monthly' : 'Per session',
      },
      { label: 'Hired', value: m.hire_date ?? '—' },
      ...(m.termination_date ? [{ label: 'Left', value: m.termination_date }] : []),
    ];
  }

  protected back(): void {
    if (window.history.length > 1) this.browser.back();
    else void this.router.navigate(['/admin/staff']);
  }

  protected selectTab(tab: Tab): void {
    this.tab.set(tab);
  }

  protected load(id: number): void {
    this.error.set(null);
    this.api.staffMember(id).subscribe({
      next: (full) => {
        this.member.set(full);
        this.seedRateForm(full.session_rates ?? []);
        this.staffForm = {
          display_name: full.display_name,
          email: full.email ?? '',
          employee_code: full.employee_code,
          hire_date: full.hire_date ?? '',
          can_edit_service_menu: full.can_edit_service_menu ?? false,
        };
        this.api.services(full.location_id).subscribe({
          next: ({ services }) => this.services.set(services),
          error: () => this.services.set([]),
        });
        if (full.engagement_type === 'manager_flat' && this.isOwner())
          this.loadMonthlyRate(full.id);
      },
      error: (err) => this.error.set(this.message(err, 'Could not load that team member.')),
    });
    this.api.workingHours(id).subscribe({
      next: ({ working_hours }) => this.hours.set(this.toRows(working_hours)),
      error: () => this.hours.set(this.emptyWeek()),
    });
    this.api.qualifications(id).subscribe({
      next: ({ qualifications }) => this.quals.set(qualifications),
      error: () => this.quals.set([]),
    });
    // Rates are the Owner's alone (BR-02); a Manager is never sent them.
    if (!this.isOwner()) return;
    this.api.sessionRates(id).subscribe({
      next: ({ session_rates }) => this.rates.set(session_rates),
      // A Manager is never given rates at all, so an error here is expected.
      error: () => this.rates.set([]),
    });
  }

  protected saveStaff(): void {
    const m = this.member();
    if (!m) return;
    this.api.updateStaff(m.id, this.staffForm).subscribe({
      next: (updated) => {
        this.member.set({ ...m, ...updated });
        this.notice.set('Profile saved.');
      },
      error: (err) => this.error.set(this.message(err, 'Could not save the profile.')),
    });
  }

  // --- working hours (Addendum §8) ------------------------------------------

  protected dayName(weekday: number): string {
    return DAY_NAMES[weekday];
  }

  protected setHours(index: number, change: Partial<HoursRow>): void {
    this.hours.update((rows) =>
      rows.map((r, i) => {
        if (i !== index) return r;
        const next = { ...r, ...change };
        // Choosing Working starts from a sensible day rather than two empty boxes.
        if (change.mode === 'working' && !next.starts_at) {
          next.starts_at = '09:00';
          next.ends_at = '17:00';
        }
        return next;
      }),
    );
  }

  protected saveHours(): void {
    const m = this.member();
    if (!m) return;
    const bad = this.hours().find(
      (d) => d.mode === 'working' && (!d.starts_at || !d.ends_at || d.ends_at <= d.starts_at),
    );
    if (bad) {
      this.error.set(`${this.dayName(bad.weekday)}: the end must be after the start.`);
      return;
    }
    this.error.set(null);
    this.savingHours.set(true);
    const days = this.hours()
      .filter((d) => d.mode !== 'unset')
      .map((d) => ({
        weekday: d.weekday,
        off: d.mode === 'off',
        starts_at: d.mode === 'working' ? d.starts_at : null,
        ends_at: d.mode === 'working' ? d.ends_at : null,
      }));
    this.api.setWorkingHours(m.id, days).subscribe({
      next: ({ working_hours }) => {
        this.savingHours.set(false);
        this.hours.set(this.toRows(working_hours));
        this.notice.set('Working hours saved. Appointments already booked are unchanged.');
      },
      error: (err) => {
        this.savingHours.set(false);
        this.error.set(this.message(err, 'Could not save the working hours.'));
      },
    });
  }

  private emptyWeek(): HoursRow[] {
    return WEEK.map((weekday) => ({ weekday, mode: 'unset', starts_at: '', ends_at: '' }));
  }

  private toRows(days: WorkingHoursDay[]): HoursRow[] {
    return WEEK.map((weekday) => {
      const d = days.find((x) => x.weekday === weekday);
      if (!d) return { weekday, mode: 'unset', starts_at: '', ends_at: '' };
      return {
        weekday,
        mode: d.off ? 'off' : 'working',
        starts_at: d.starts_at ?? '',
        ends_at: d.ends_at ?? '',
      };
    });
  }

  // --- qualifications (BR-01) --------------------------------------------

  protected qualified(serviceId: number): boolean {
    return this.quals().some((q) => q.service_id === serviceId);
  }

  protected toggleQualification(serviceId: number, on: boolean): void {
    const m = this.member();
    if (!m) return;
    const current = this.quals().map((q) => q.service_id);
    const next = on ? [...current, serviceId] : current.filter((id) => id !== serviceId);
    this.api.setQualifications(m.id, next).subscribe({
      next: ({ qualifications }) => {
        this.quals.set(qualifications);
        this.notice.set('Qualifications saved.');
      },
      // The API refuses to leave a therapist with none — they would vanish from every search.
      error: (err) => this.error.set(this.message(err, 'Could not save qualifications.')),
    });
  }

  // --- pay (BR-35) --------------------------------------------------------

  protected saveRates(): void {
    const m = this.member();
    if (!m) return;
    this.error.set(null);
    this.api
      .setSessionRates(m.id, this.ladderPayload(), this.rateEffectiveFrom, this.rateNote)
      .subscribe({
        next: ({ session_rates }) => {
          this.rates.set(session_rates);
          this.rateNote = '';
          this.notice.set(
            `New rates take effect ${this.rateEffectiveFrom}. Earlier pay is unchanged.`,
          );
        },
        error: (err) => this.error.set(this.message(err, 'Could not save rates.')),
      });
  }

  protected saveMonthlyRate(): void {
    const m = this.member();
    if (!m) return;
    this.api
      .setMonthlyRate(
        m.id,
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
        error: (err) => this.error.set(this.message(err, 'Could not save the monthly rate.')),
      });
  }

  // --- offboarding (BR-02) ------------------------------------------------

  protected async offboard(event?: Event): Promise<void> {
    (event?.target as HTMLElement | undefined)?.closest('details')?.removeAttribute('open');
    const m = this.member();
    if (!m) return;
    const { confirmed, value } = await this.confirm.ask({
      title: `Offboard ${m.display_name}?`,
      message:
        'Their sign-in is disabled and they drop out of every schedule. Their history and pay records stay. This is refused while they still have appointments booked.',
      confirmLabel: 'Offboard',
      tone: 'danger',
      field: {
        label: 'Last working day',
        type: 'date',
        required: true,
        initial: todayIn(null),
      },
    });
    if (!confirmed) return;
    this.error.set(null);
    this.api.offboardStaff(m.id, value).subscribe({
      next: (updated) => {
        this.member.set({ ...m, ...updated });
        this.notice.set(`${m.display_name} has been offboarded.`);
      },
      error: (err) => {
        const ids = err?.error?.error?.details?.appointment_ids as number[] | undefined;
        this.error.set(
          ids?.length
            ? `Still has booked appointments (${ids.join(', ')}). Reassign or cancel them first.`
            : this.message(err, 'Could not offboard.'),
        );
      },
    });
  }

  private ladderPayload(): { duration_minutes: number; rate_cents: number }[] {
    return LADDER.map((d) => ({
      duration_minutes: d,
      rate_cents: Math.round((this.rateForm[d] ?? 0) * 100),
    }));
  }

  protected seedRateForm(rates: SessionRate[]): void {
    const form: Record<number, number> = {};
    for (const d of LADDER) {
      const open = rates.find((r) => r.duration_minutes === d && !r.effective_to);
      form[d] = open ? open.rate_cents / 100 : 0;
    }
    this.rateForm = form;
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
