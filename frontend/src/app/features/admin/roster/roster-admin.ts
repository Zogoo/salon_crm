import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { RosterShift, StaffMember } from '../../../core/models';
import { LocationContextService } from '../../../core/services/location-context.service';
import { MassagelabService } from '../../../core/services/massagelab.service';
import { todayIn } from '../../../core/salon-date';

/**
 * Doc 01 §3.3 / doc 05 §"Shifts" — the roster a Manager actually edits.
 *
 * Two rules shape this screen. A shift is drafted and then published, and
 * publishing is all-or-nothing, because a half-published week leaves some
 * therapists silently unbookable. And BR-07 refuses any edit that would leave
 * an appointment uncovered — the API answers with the appointment ids, which
 * is what the front desk needs to go and move them.
 */
@Component({
  selector: 'app-roster-admin',
  imports: [FormsModule],
  templateUrl: './roster-admin.html',
  styleUrl: './roster-admin.scss',
})
export class RosterAdminPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly shifts = signal<RosterShift[]>([]);
  protected readonly staff = signal<StaffMember[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly selectedIds = signal<number[]>([]);

  protected from = '';
  protected to = '';
  protected newShift = { staff_profile_id: 0, work_date: '', starts_at: '09:00', ends_at: '22:00' };
  protected editing: RosterShift | null = null;
  protected edit = { work_date: '', starts_at: '', ends_at: '' };

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      const today = todayIn(this.ctx.current()?.timezone);
      this.from = today;
      this.to = this.addDays(today, 13);
      this.newShift.work_date = today;
      this.reload();
      this.loadStaff();
    });
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    this.reload();
    this.loadStaff();
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.selectedIds.set([]);
    this.api.roster(loc.id, this.from, this.to).subscribe({
      next: ({ shifts }) => this.shifts.set(shifts),
      error: (err) => this.error.set(this.message(err, 'Could not load the roster')),
    });
  }

  protected drafts(): RosterShift[] {
    return this.shifts().filter((s) => s.status !== 'published');
  }

  protected nameFor(shift: RosterShift): string {
    return (
      shift.display_name ??
      this.staff().find((s) => s.id === shift.staff_profile_id)?.display_name ??
      `#${shift.staff_profile_id}`
    );
  }

  protected wallClock(iso: string): string {
    // The API sends the salon's offset; read the clock off the string rather
    // than converting through the browser's zone.
    return iso.slice(11, 16);
  }

  // --- create, edit, delete ---

  protected create(): void {
    const loc = this.ctx.current();
    if (!loc || !this.newShift.staff_profile_id) return;
    this.clear();

    this.api
      .createShift({
        location_id: loc.id,
        staff_profile_id: this.newShift.staff_profile_id,
        work_date: this.newShift.work_date,
        starts_at: this.newShift.starts_at,
        ends_at: this.newShift.ends_at,
      })
      .subscribe({
        next: () => {
          this.notice.set('Shift drafted. Publish it to make the therapist bookable.');
          this.reload();
        },
        error: (err) => this.error.set(this.message(err, 'Could not create that shift')),
      });
  }

  protected startEdit(shift: RosterShift): void {
    this.editing = shift;
    this.edit = {
      work_date: shift.work_date,
      starts_at: this.wallClock(shift.starts_at),
      ends_at: this.wallClock(shift.ends_at),
    };
  }

  protected saveEdit(): void {
    if (!this.editing) return;
    this.clear();

    this.api.updateShift(this.editing.id, this.edit).subscribe({
      next: () => {
        this.editing = null;
        this.notice.set('Shift updated.');
        this.reload();
      },
      error: (err) => this.error.set(this.orphanMessage(err, 'Could not update that shift')),
    });
  }

  protected remove(shift: RosterShift): void {
    this.clear();
    this.api.deleteShift(shift.id).subscribe({
      next: () => {
        this.notice.set('Shift removed.');
        this.reload();
      },
      error: (err) => this.error.set(this.orphanMessage(err, 'Could not remove that shift')),
    });
  }

  // --- publishing ---

  protected toggleSelected(id: number, on: boolean): void {
    this.selectedIds.update((ids) => (on ? [...ids, id] : ids.filter((x) => x !== id)));
  }

  protected publish(): void {
    const ids = this.selectedIds();
    if (!ids.length) return;
    this.clear();

    this.api.publishShifts(ids).subscribe({
      next: ({ published }) => {
        this.notice.set(`Published ${published.length} shift(s).`);
        this.reload();
      },
      error: (err) => {
        // All-or-nothing: nothing was published, and the clash says which.
        const conflicts = err?.error?.error?.details?.conflicts as
          | { shift_id: number; errors: string[] }[]
          | undefined;
        this.error.set(
          conflicts?.length
            ? `Nothing was published. Shift ${conflicts[0].shift_id}: ${conflicts[0].errors.join(', ')}`
            : this.message(err, 'Could not publish'),
        );
      },
    });
  }

  private loadStaff(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.staffList(loc.id).subscribe({
      next: ({ staff }) => {
        this.staff.set(staff);
        this.newShift.staff_profile_id = staff[0]?.id ?? 0;
      },
      error: () => this.staff.set([]),
    });
  }

  private clear(): void {
    this.error.set(null);
    this.notice.set(null);
  }

  private addDays(date: string, days: number): string {
    const d = new Date(`${date}T00:00:00`);
    d.setDate(d.getDate() + days);
    return d.toISOString().slice(0, 10);
  }

  /** BR-07 answers with the appointments that would be left uncovered. */
  private orphanMessage(err: unknown, fallback: string): string {
    const e = err as { error?: { error?: { code?: string; details?: { appointment_ids?: number[] } } } };
    const ids = e?.error?.error?.details?.appointment_ids;
    if (ids?.length) {
      return `That would leave appointment(s) ${ids.join(', ')} without a therapist. Move them first.`;
    }
    return this.message(err, fallback);
  }

  private message(err: unknown, fallback: string): string {
    const e = err as { error?: { error?: { message?: string; code?: string } | string } };
    const body = e?.error?.error;
    if (typeof body === 'string') return body;
    return body?.message ?? body?.code ?? fallback;
  }
}
