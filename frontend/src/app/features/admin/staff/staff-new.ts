import { LocationScope } from '../../../shared/location-scope';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { Service } from '../../../core/models';
import { LocationContextService } from '../../../core/services/location-context.service';
import { MassagelabService } from '../../../core/services/massagelab.service';
import { todayIn } from '../../../core/salon-date';
import { UiBanner, UiButton, UiCard, UiField, UiPage } from '../../../ui';
import { LADDER } from './staff-detail';

/**
 * Doc 05 §6 — onboarding is one step: sign-in, profile, qualifications and pay.
 * Half a therapist is worse than none: one without a ladder books fine and
 * then fails at payroll, so the form will not submit a ladder of zeros.
 */
@Component({
  selector: 'app-staff-new',
  imports: [FormsModule, RouterLink, UiPage, LocationScope, UiCard, UiField, UiButton, UiBanner],
  templateUrl: './staff-new.html',
  styleUrls: ['../../../ui/layouts.scss', './staff.scss'],
})
export class StaffNewPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  protected readonly ctx = inject(LocationContextService);

  protected readonly services = signal<Service[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly saving = signal(false);
  protected readonly ladder = LADDER;
  protected rateForm: Record<number, number> = { 30: 0, 45: 0, 60: 0, 75: 0, 90: 0, 120: 0 };
  protected form = {
    display_name: '',
    email: '',
    employee_code: '',
    role: 'staff',
    engagement_type: 'contractor_1099',
    rates_effective_from: '',
  };

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.form.rates_effective_from = todayIn(this.ctx.current()?.timezone);
      const loc = this.ctx.current();
      if (loc) this.api.services(loc.id).subscribe(({ services }) => this.services.set(services));
    });
  }

  /** Role decides how they are paid, so the two never disagree. */
  protected onRole(role: string): void {
    this.form.role = role;
    this.form.engagement_type = role === 'manager' ? 'manager_flat' : 'contractor_1099';
  }

  protected create(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    const manager = this.form.engagement_type === 'manager_flat';
    const ladder = LADDER.map((d) => ({
      duration_minutes: d,
      rate_cents: Math.round((this.rateForm[d] ?? 0) * 100),
    }));
    if (!this.form.display_name.trim() || !this.form.email.trim()) {
      this.error.set('Name and email are required.');
      return;
    }
    if (!manager && ladder.some((r) => r.rate_cents === 0)) {
      this.error.set(
        'Set all six session rates — a missing rate means pay silently fails on those bookings.',
      );
      return;
    }
    this.error.set(null);
    this.saving.set(true);
    this.api
      .createStaff({
        ...this.form,
        location_id: loc.id,
        service_ids: this.services().map((s) => s.id),
        session_rates: manager ? undefined : ladder,
      })
      .subscribe({
        next: (created) => {
          this.saving.set(false);
          void this.router.navigate(['/admin/staff', created.id], { replaceUrl: true });
        },
        error: (err) => {
          this.saving.set(false);
          const body = err?.error?.error;
          this.error.set(
            typeof body === 'string' ? body : (body?.message ?? 'Could not add that team member.'),
          );
        },
      });
  }
}
