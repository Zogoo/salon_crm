import { Component, HostListener, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { switchMap } from 'rxjs';

import { Appointment, CareNote, DayBoard, Room, Service, StaffMember } from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';
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
  UiSheet,
  UiTable,
  humanise,
  statusTone,
} from '../../ui';

interface Placed {
  appointment: Appointment;
  leftPct: number;
  widthPct: number;
  bufferPct: number;
}

interface DragState {
  appointment: Appointment;
  startX: number;
  startY: number;
  moved: boolean;
}

/** What the desk is told when the API refuses, keyed by the error code. */
const MESSAGES: Record<string, string> = {
  therapist_assignment_required: 'Assign the therapist before checkout.',
  discount_above_manager_limit:
    'That is more than a Manager can discount on this order. Ask the Owner to apply it.',
  discount_exceeds_remaining: 'The discount is larger than what is left to pay.',
  discount_not_permitted: 'Only the Owner or a Manager can give a discount.',
  reason_required: 'Give a reason for the discount.',
  order_has_payments:
    'Money has already been taken for this visit, so it cannot be changed here. Void or refund the payment at checkout first.',
  discount_exceeds_order: 'That change would leave the discount larger than the bill.',
  price_below_deposit:
    'The new price would be less than the deposit already taken. Refund the deposit first.',
  deposit_exceeds_price: 'A deposit cannot be more than the appointment costs.',
  deposit_already_recorded: 'A deposit is already recorded for this appointment.',
  no_held_deposit: 'There is no deposit held for this appointment.',
};

const MOVABLE = ['pending_approval', 'scheduled', 'checked_in'];

/** FRS §6 — rooms as rows, time across, 09:00–22:00. */
@Component({
  selector: 'app-day-board',
  imports: [
    FormsModule,
    DecimalPipe,
    WallClockPipe,
    UiPage,
    UiCard,
    UiTable,
    UiChip,
    UiEmpty,
    UiBanner,
    UiButton,
    UiField,
    UiSheet,
    UiFacts,
  ],
  templateUrl: './day-board.html',
  styleUrls: ['./day-board.scss', './day-board-controls.scss'],
})
export class DayBoardPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  protected readonly ctx = inject(LocationContextService);
  protected readonly auth = inject(AuthService);

  protected readonly board = signal<DayBoard | null>(null);
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly selected = signal<Appointment | null>(null);
  protected readonly careNotes = signal<CareNote[]>([]);
  protected readonly services = signal<Service[]>([]);
  protected readonly staff = signal<StaffMember[]>([]);
  protected readonly checkoutPrompt = signal(false);
  protected readonly dragging = signal<{ id: number; dx: number; dy: number } | null>(null);
  protected newCareNote = '';
  protected correctingNoteId: number | null = null;
  protected appointmentNote = '';
  protected rescheduleDate = '';
  protected rescheduleTime = '';
  protected rescheduleRoomId: number | null = null;
  protected assignmentIds: number[] = [];
  protected extraVariantId: number | null = null;
  protected replacementVariantId: number | null = null;
  protected ratingScore: number | null = null;
  protected ratingFeedback = '';
  protected repeatForm = { interval_weeks: 1, count: 3 };
  protected readonly repeatNotice = signal('');
  protected discount = { dollars: 0, reason: '' };
  protected readonly discountNotice = signal('');
  protected deposit = { dollars: 0, method: 'card', reference: '' };
  protected readonly depositMethods = ['card', 'cash', 'zelle', 'other'];
  protected readonly depositNotice = signal('');
  protected confirmingDepositRefund = false;
  protected date = '';

  private drag: DragState | null = null;
  private suppressClick = false;

  /** Names the location, so a board is never read against the wrong salon. */
  protected readonly subtitle = computed(
    () =>
      `Every room and therapist at ${this.ctx.current()?.name ?? 'this location'}, hour by hour.`,
  );
  protected readonly canBook = computed(() => this.auth.user()?.role !== 'staff');
  protected readonly isTherapist = computed(() => this.auth.user()?.role === 'staff');

  protected readonly discountHint = computed(() => {
    if (this.auth.user()?.role === 'owner') return 'Recorded with your name and the reason.';
    const pct = this.ctx.current()?.manager_discount_limit_percent;
    return pct === undefined
      ? 'Recorded with your name and the reason.'
      : `Managers can discount up to ${pct}% of the services on one visit; above that, ask the Owner.`;
  });

  protected readonly emptyHint = computed(() =>
    this.canBook()
      ? 'Book one, or check the date above — the board shows a single day.'
      : 'Check the date above; the board shows a single day.',
  );

  protected tone(status: string) {
    return statusTone(status);
  }
  protected humanStatus(status: string) {
    return humanise(status);
  }
  protected destructive(action: string) {
    return action === 'cancelled' || action === 'no_show';
  }

  protected summary(appt: Appointment): Fact[] {
    const money = (cents: number) => `$${(cents / 100).toFixed(2)}`;
    const facts: Fact[] = [
      { label: 'Time', value: `${this.clock(appt.starts_at)}–${this.clock(appt.service_ends_at)}` },
      { label: 'Room', value: appt.room?.name },
      {
        label: appt.therapists.length > 1 ? 'Therapists' : 'Therapist',
        value: appt.therapists.map((t) => t.display_name).join(', ') || 'Unassigned',
      },
      { label: 'Total', value: money(appt.total_price_cents) },
    ];
    if (appt.deposit) {
      const d = appt.deposit;
      const hint =
        d.status === 'held'
          ? `Held for the client; comes off the bill at checkout.`
          : d.status === 'forfeited'
            ? `${money(d.fee_cents)} kept as the fee, ${money(d.refunded_cents)} given back.`
            : humanise(d.status);
      facts.push({
        label: 'Deposit',
        value: `${money(d.amount_cents)} · ${humanise(d.method)}`,
        hint,
      });
    }
    if (appt.fee_charged_cents) {
      // BR-19: recorded as owed, and saying so stops it being read as taken.
      facts.push({
        label: 'Fee owed',
        value: money(appt.fee_charged_cents),
        hint: 'Owed, not yet collected.',
      });
    }
    return facts;
  }

  protected preferenceFacts(appt: Appointment): Fact[] {
    const p = appt.preference;
    if (!p) return [];
    return (
      [
        { label: 'Pressure', value: p.pressure },
        { label: 'Attention', value: p.attention_areas },
        { label: 'Avoid', value: p.avoid_areas },
        { label: 'Other', value: p.other_requests },
      ] as Fact[]
    ).filter((f) => !!f.value);
  }

  /** The salon's wall clock, read straight off the ISO string. */
  private clock(iso: string): string {
    return iso.slice(11, 16);
  }

  protected readonly hours = computed(() => {
    const b = this.board();
    if (!b) return [];
    const open = Number(b.opens_at.slice(0, 2));
    const close = Number(b.closes_at.slice(0, 2));
    return Array.from({ length: close - open + 1 }, (_, i) => open + i);
  });

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      this.date ||= todayIn(this.ctx.current()?.timezone);
      this.loadEditors();
      this.reload();
    });
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.loading.set(true);
    this.error.set(null);
    this.api.dayBoard(loc.id, this.date).subscribe({
      next: (board) => {
        this.board.set(board);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.error ?? 'Could not load the schedule');
        this.loading.set(false);
      },
    });
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    this.selected.set(null);
    this.loadEditors();
    this.reload();
  }

  protected shiftDay(days: number): void {
    const d = new Date(this.date);
    d.setDate(d.getDate() + days);
    this.date = d.toISOString().slice(0, 10);
    this.reload();
  }

  /** Positions an appointment as a percentage of the open day. */
  protected placed(room: Room): Placed[] {
    const b = this.board();
    if (!b) return [];
    const open = this.toMinutes(b.opens_at);
    const close = this.toMinutes(b.closes_at);
    const span = close - open;

    return b.appointments
      .filter((a) => a.room.id === room.id)
      .map((a) => {
        const start = this.minutesOfDay(a.starts_at);
        const serviceEnd = this.minutesOfDay(a.service_ends_at);
        const end = this.minutesOfDay(a.ends_at);
        return {
          appointment: a,
          leftPct: ((start - open) / span) * 100,
          widthPct: ((serviceEnd - start) / span) * 100,
          // The 15-minute buffer is real reserved time, so it is drawn — but a
          // no-show holds nothing, so it gets none.
          bufferPct: a.status === 'no_show' ? 0 : ((end - serviceEnd) / span) * 100,
        };
      });
  }

  protected select(appointment: Appointment): void {
    // The click that ends a drag is not a request to open the appointment.
    if (this.suppressClick) return;
    this.newCareNote = '';
    this.careNotes.set([]);
    this.api.appointment(appointment.id).subscribe({
      next: (full) => this.prepareSelection(full),
      error: () => this.selected.set(appointment),
    });
    // Every read is audit-logged server-side — it is the only way to answer
    // "who looked at this" (doc 04 §5).
    this.api.careNotes(appointment.id).subscribe({
      next: ({ care_notes }) => this.careNotes.set(care_notes),
      error: () => this.careNotes.set([]),
    });
  }

  protected extras(): { id: number; label: string }[] {
    return this.services()
      .filter((service) => service.kind !== 'standard')
      .flatMap((service) =>
        service.variants.map((variant) => ({
          id: variant.id,
          label: `${service.name} · $${(variant.price_cents / 100).toFixed(2)}`,
        })),
      );
  }

  protected standardVariants(): { id: number; label: string }[] {
    return this.services()
      .filter((service) => service.kind === 'standard')
      .flatMap((service) =>
        service.variants.map((variant) => ({
          id: variant.id,
          label: `${service.name} · ${variant.duration_minutes} min · $${(variant.price_cents / 100).toFixed(2)}`,
        })),
      );
  }

  protected replaceService(appointment: Appointment): void {
    if (!this.replacementVariantId) return;
    const extras =
      appointment.items
        ?.filter((item) => item.kind !== 'service')
        .map((item) => item.service_variant_id) ?? [];
    this.api
      .replaceAppointmentService(appointment.id, [this.replacementVariantId, ...extras])
      .subscribe({
        next: (fresh) => {
          this.prepareSelection(fresh);
          this.reload();
        },
        error: (err) => this.error.set(this.apiMessage(err, 'Could not change the service')),
      });
  }

  protected saveInternalNote(appointment: Appointment): void {
    this.api
      .updateAppointment(appointment.id, { appointment_note: this.appointmentNote })
      .subscribe({
        next: (updated) => {
          this.prepareSelection(updated);
          this.error.set(null);
        },
        error: (err) => this.error.set(this.apiMessage(err, 'Could not save the note')),
      });
  }

  protected addExtra(appointment: Appointment): void {
    if (!this.extraVariantId) return;
    this.api.addAppointmentItems(appointment.id, [this.extraVariantId]).subscribe({
      next: (updated) => {
        this.extraVariantId = null;
        this.prepareSelection(updated);
        this.reload();
      },
      error: (err) => this.error.set(this.apiMessage(err, 'Could not add that item')),
    });
  }

  protected removeExtra(appointment: Appointment, itemId: number): void {
    this.api.removeAppointmentItem(appointment.id, itemId).subscribe({
      next: (updated) => {
        this.prepareSelection(updated);
        this.reload();
      },
      error: (err) => this.error.set(this.apiMessage(err, 'Could not remove that item')),
    });
  }

  /**
   * The order this opens stays in step with the appointment until money is
   * taken, so the desk can still add an extra or move the visit afterwards.
   */
  protected applyDiscount(appointment: Appointment): void {
    const amountCents = Math.round(this.discount.dollars * 100);
    const reason = this.discount.reason.trim();
    if (amountCents <= 0 || !reason) return;

    this.error.set(null);
    this.discountNotice.set('');
    this.api
      .openOrder(appointment.id)
      .pipe(switchMap((order) => this.api.applyDiscount(order.id, amountCents, reason)))
      .subscribe({
        next: () => {
          this.discountNotice.set(`Discount of $${this.discount.dollars.toFixed(2)} applied.`);
          this.discount = { dollars: 0, reason: '' };
        },
        error: (err) => this.error.set(this.apiMessage(err, 'Could not apply the discount')),
      });
  }

  /** Feedback 3.2: money taken before the visit, held until checkout. */
  protected recordDeposit(appointment: Appointment): void {
    const cents = Math.round(this.deposit.dollars * 100);
    if (cents <= 0) return;
    this.error.set(null);
    this.depositNotice.set('');
    this.api
      .recordDeposit(appointment.id, cents, this.deposit.method, this.deposit.reference.trim())
      .subscribe({
        next: (updated) => {
          this.prepareSelection(updated);
          this.depositNotice.set(`Deposit of $${(cents / 100).toFixed(2)} recorded.`);
        },
        error: (err) => this.error.set(this.apiMessage(err, 'Could not record the deposit')),
      });
  }

  protected refundDeposit(appointment: Appointment): void {
    if (!this.confirmingDepositRefund) {
      this.confirmingDepositRefund = true;
      return;
    }
    this.api.refundDeposit(appointment.id).subscribe({
      next: (updated) => {
        this.prepareSelection(updated);
        this.depositNotice.set('Deposit recorded as given back.');
      },
      error: (err) => this.error.set(this.apiMessage(err, 'Could not refund the deposit')),
    });
  }

  protected toggleAssignee(id: number, on: boolean): void {
    this.assignmentIds = on
      ? [...this.assignmentIds, id]
      : this.assignmentIds.filter((staffId) => staffId !== id);
  }

  protected assignStaff(appointment: Appointment): void {
    this.api.assignAppointmentStaff(appointment.id, this.assignmentIds).subscribe({
      next: (updated) => {
        this.prepareSelection(updated);
        this.reload();
      },
      error: (err) => this.error.set(this.apiMessage(err, 'Could not assign that therapist')),
    });
  }

  protected reschedule(appointment: Appointment): void {
    if (!this.rescheduleDate || !this.rescheduleTime || !this.rescheduleRoomId) return;
    this.moveAppointment(
      appointment,
      this.localIso(appointment, this.rescheduleDate, this.rescheduleTime),
      this.rescheduleRoomId,
    );
  }

  protected repeatAppointment(appointment: Appointment): void {
    this.repeatNotice.set('');
    this.api
      .repeatAppointment(appointment.id, this.repeatForm.interval_weeks, this.repeatForm.count)
      .subscribe({
        next: ({ appointments }) => {
          this.repeatNotice.set(`${appointments.length} future appointments booked.`);
          this.reload();
        },
        error: (err) => this.error.set(this.apiMessage(err, 'Could not create the repeats')),
      });
  }

  // --- moving an appointment --------------------------------------------
  //
  // Pointer events rather than HTML5 drag-and-drop: native drag never starts
  // from a finger, and the front desk works on a tablet (feedback 1.2).

  protected canMove(appointment: Appointment): boolean {
    return this.canBook() && MOVABLE.includes(appointment.status);
  }

  protected pointerDown(event: PointerEvent, appointment: Appointment): void {
    if (!this.canMove(appointment) || event.button > 0) return;
    this.drag = { appointment, startX: event.clientX, startY: event.clientY, moved: false };
  }

  @HostListener('document:pointermove', ['$event'])
  protected pointerMove(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag) return;
    const dx = event.clientX - drag.startX;
    const dy = event.clientY - drag.startY;
    // A small wobble is still a tap.
    if (!drag.moved && Math.hypot(dx, dy) < 8) return;
    drag.moved = true;
    this.dragging.set({ id: drag.appointment.id, dx, dy });
  }

  @HostListener('document:pointerup', ['$event'])
  protected pointerUp(event: PointerEvent): void {
    const drag = this.drag;
    this.drag = null;
    this.dragging.set(null);
    if (!drag?.moved) return;

    this.suppressClick = true;
    setTimeout(() => (this.suppressClick = false));
    const lane = (document.elementsFromPoint?.(event.clientX, event.clientY) ?? []).find(
      (el): el is HTMLElement => el instanceof HTMLElement && !!el.dataset['laneRoom'],
    );
    const room = this.board()?.rooms.find((r) => String(r.id) === lane?.dataset['laneRoom']);
    if (lane && room) this.dropAt(drag.appointment, room, lane, event.clientX);
  }

  @HostListener('document:pointercancel')
  protected pointerCancel(): void {
    this.drag = null;
    this.dragging.set(null);
  }

  protected dragTransform(id: number): string | null {
    const d = this.dragging();
    return d?.id === id ? `translate(${d.dx}px, ${d.dy}px)` : null;
  }

  /** Snaps the drop point to the 15-minute grid, inside opening hours. */
  protected dropAt(appointment: Appointment, room: Room, lane: HTMLElement, clientX: number): void {
    const board = this.board();
    if (!board) return;
    const rect = lane.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    const open = this.toMinutes(board.opens_at);
    const close = this.toMinutes(board.closes_at);
    const minutes = Math.round((open + ratio * (close - open)) / 15) * 15;
    const latest = close - appointment.duration_minutes - 15;
    const safe = Math.max(open, Math.min(minutes, latest));
    const time = `${String(Math.floor(safe / 60)).padStart(2, '0')}:${String(safe % 60).padStart(2, '0')}`;
    this.moveAppointment(appointment, this.localIso(appointment, this.date, time), room.id);
  }

  /** BR-44: append-only. A correction is a new note, never an edit. */
  protected addCareNote(appointment: Appointment): void {
    const body = this.newCareNote.trim();
    if (!body) return;
    this.api.addCareNote(appointment.id, body).subscribe({
      next: (note) => {
        this.careNotes.set([...this.careNotes(), note]);
        this.newCareNote = '';
      },
      error: (err) =>
        this.error.set(
          err?.error?.error?.code === 'not_assigned_to_this_appointment'
            ? 'Only a therapist on this appointment can write its care note.'
            : 'Could not save the note',
        ),
    });
  }

  protected correctCareNote(note: CareNote): void {
    const body = this.newCareNote.trim();
    if (!body) return;
    this.api.supersedeCareNote(note.id, body).subscribe({
      next: (correction) => {
        this.careNotes.set([...this.careNotes(), correction]);
        this.newCareNote = '';
        this.correctingNoteId = null;
      },
      error: () => this.error.set('Could not save the correction'),
    });
  }

  protected checkout(appointment: Appointment): void {
    if (appointment.assignment_pending) {
      this.error.set('Assign the therapist before checkout.');
      return;
    }
    if (appointment.status === 'completed') {
      void this.router.navigate(['/checkout', appointment.id]);
      return;
    }
    this.checkoutPrompt.set(true);
    this.ratingScore = null;
    this.ratingFeedback = '';
  }

  protected submitRatingAndCheckout(appointment: Appointment): void {
    if (!this.ratingScore) return;
    this.api
      .submitRating({
        appointment_id: appointment.id,
        score: this.ratingScore,
        feedback: this.ratingFeedback || undefined,
      })
      .subscribe({
        next: () => this.completeAndCheckout(appointment),
        error: (err) => {
          if (err?.error?.error?.code === 'already_rated') this.completeAndCheckout(appointment);
          else this.error.set(this.apiMessage(err, 'Could not save the rating'));
        },
      });
  }

  /** A client who would rather not rate is not held at the desk for it. */
  protected declineRatingAndCheckout(appointment: Appointment): void {
    this.completeAndCheckout(appointment);
  }

  protected rebook(appointment: Appointment): void {
    const service = appointment.items?.find((item) => item.kind === 'service');
    void this.router.navigate(['/book'], {
      queryParams: {
        date: this.date,
        client_id: appointment.client.id,
        variant_id: service?.service_variant_id,
      },
    });
  }

  protected focusEditor(testId: string): void {
    setTimeout(() => {
      (document.querySelector(`[data-testid="${testId}"]`) as HTMLElement | null)?.focus();
    });
  }

  protected transition(appointment: Appointment, to: string): void {
    this.api.transition(appointment.id, to).subscribe({
      next: (updated) => {
        this.selected.set(updated);
        this.reload();
      },
      error: (err) => this.error.set(this.apiMessage(err, 'That change is not allowed')),
    });
  }

  protected nextActions(status: string): string[] {
    return (
      {
        pending_approval: ['cancelled'],
        scheduled: ['checked_in', 'cancelled', 'no_show'],
        // A client can check in and then leave; that is a cancellation.
        checked_in: ['in_progress', 'cancelled', 'no_show'],
        in_progress: ['completed'],
      }[status] ?? []
    );
  }

  protected label(action: string): string {
    return (
      {
        checked_in: 'Check in',
        in_progress: 'Start',
        completed: 'Complete',
        cancelled: 'Cancel',
        no_show: 'No-show',
      }[action] ?? action
    );
  }

  /**
   * Doc 01 §6 names a printable daily schedule as the fallback for the system
   * being unavailable, so this is a real operational requirement rather than a
   * convenience: the front desk needs the day on paper before they need it.
   */
  protected print(): void {
    window.print();
  }

  protected newBooking(): void {
    void this.router.navigate(['/book'], { queryParams: { date: this.date } });
  }

  private prepareSelection(appointment: Appointment): void {
    this.selected.set(appointment);
    this.appointmentNote = appointment.appointment_note ?? '';
    this.rescheduleDate = appointment.starts_at.slice(0, 10);
    this.rescheduleTime = this.clock(appointment.starts_at);
    this.rescheduleRoomId = appointment.room.id;
    this.assignmentIds = appointment.therapists.map((member) => member.id);
    this.replacementVariantId =
      appointment.items?.find((item) => item.kind === 'service')?.service_variant_id ?? null;
    this.checkoutPrompt.set(false);
    this.discount = { dollars: 0, reason: '' };
    this.discountNotice.set('');
    this.deposit = { dollars: 0, method: 'card', reference: '' };
    this.depositNotice.set('');
    this.confirmingDepositRefund = false;
  }

  /** One server call: checked in → in progress → completed, then the order. */
  private completeAndCheckout(appointment: Appointment): void {
    if (appointment.status === 'completed') {
      void this.router.navigate(['/checkout', appointment.id]);
      return;
    }
    this.api.completeForCheckout(appointment.id).subscribe({
      next: () => void this.router.navigate(['/checkout', appointment.id]),
      error: (err) => this.error.set(this.apiMessage(err, 'Could not prepare checkout')),
    });
  }

  private moveAppointment(appointment: Appointment, startAt: string, roomId: number): void {
    const staffIds = appointment.assignment_pending
      ? undefined
      : appointment.therapists.map((member) => member.id);
    this.error.set(null);
    this.api.rescheduleAppointment(appointment.id, startAt, roomId, staffIds).subscribe({
      next: (fresh) => {
        this.prepareSelection(fresh);
        this.date = fresh.starts_at.slice(0, 10);
        this.reload();
      },
      error: (err) => this.error.set(this.apiMessage(err, 'Could not reschedule')),
    });
  }

  private localIso(appointment: Appointment, date: string, time: string): string {
    const offset = /([+-]\d{2}:\d{2})$/.exec(appointment.starts_at)?.[1] ?? '';
    return `${date}T${time}:00${offset}`;
  }

  private loadEditors(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.services(loc.id).subscribe(({ services }) => this.services.set(services));
    this.api.staff(loc.id).subscribe(({ staff }) => this.staff.set(staff));
  }

  private apiMessage(err: any, fallback: string): string {
    const body = err?.error?.error;
    if (typeof body === 'string') return MESSAGES[body] ?? body;
    return (body?.code && MESSAGES[body.code]) || body?.message || body?.code || fallback;
  }

  private toMinutes(hhmm: string): number {
    const [h, m] = hhmm.split(':').map(Number);
    return h * 60 + m;
  }

  /** Minutes since midnight in the *salon's* wall clock — see WallClockPipe. */
  private minutesOfDay(iso: string): number {
    const m = /T(\d{2}):(\d{2})/.exec(iso);
    return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
  }
}
