import { LocationScope } from '../../shared/location-scope';
import { Component, HostListener, OnInit, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { switchMap } from 'rxjs';

import { Appointment, CareNote, DayBoard, Room, Service, StaffMember } from '../../core/models';
import { WallClockPipe } from '../../core/pipes/wall-clock.pipe';
import { AuthService } from '../../core/services/auth.service';
import { LocationContextService } from '../../core/services/location-context.service';
import { MassagelabService } from '../../core/services/massagelab.service';
import { todayIn } from '../../core/salon-date';
import {
  Fact,
  ConfirmService,
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
  /** Pixels in the whole open day, so a pointer distance converts to minutes. */
  laneWidth: number;
  moved: boolean;
}

/** Where a dragged block would land if it were released now. */
interface DropPreview {
  roomId: number;
  roomName: string;
  start: number;
  leftPct: number;
  widthPct: number;
  label: string;
  changed: boolean;
}

/** A line on the timeline, at the same scale the blocks are drawn on. */
interface RulerMark {
  minutes: number;
  pct: number;
  hour: boolean;
  label: string;
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

type PanelSection = 'service' | 'deposit' | 'discount' | 'reschedule' | 'repeat' | 'note';

/** FRS §6 — rooms as rows, time across, 09:00–22:00. */
@Component({
  selector: 'app-day-board',
  imports: [
    FormsModule,
    DecimalPipe,
    WallClockPipe,
    UiPage,
    LocationScope,
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
  styleUrls: ['../../ui/layouts.scss', './day-board.scss', './day-board-controls.scss'],
})
export class DayBoardPage implements OnInit {
  private readonly api = inject(MassagelabService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly confirm = inject(ConfirmService);
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
  /** The appointment being dragged, drawn faded where it still is. */
  protected readonly dragging = signal<number | null>(null);
  protected readonly preview = signal<DropPreview | null>(null);
  /** Which edit section of the panel is unfolded — one at a time. */
  protected readonly openSection = signal<PanelSection | null>(null);
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
  protected readonly subtitle = computed(() =>
    // A therapist only receives their own appointments, so the page must not promise everyone's.
    this.isTherapist()
      ? `Your appointments at ${this.ctx.current()?.name ?? 'this location'}, hour by hour.`
      : `Every room and therapist at ${this.ctx.current()?.name ?? 'this location'}, hour by hour.`,
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

  /** "Couple room · 2 seats" rather than the stored "couple · seats 2". */
  protected roomLabel(room: Room): string {
    const seats = room.client_capacity === 1 ? '1 seat' : `${room.client_capacity} seats`;
    return `${humanise(room.room_type)} room · ${seats}`;
  }

  /** A narrow block truncates, so the full line is one hover away. */
  protected blockTitle(appt: Appointment): string {
    const who = appt.assignment_pending
      ? 'No preference'
      : appt.therapists.map((t) => t.display_name).join(', ') || 'Unassigned';
    return `${appt.client.full_name} · ${this.timeRange(appt)} · ${who} · ${humanise(appt.status)}`;
  }

  /** "13:00–14:00": the block says exactly when, so its position is never read as a guess. */
  protected timeRange(appt: Appointment): string {
    return `${this.clock(appt.starts_at)}–${this.clock(appt.service_ends_at)}`;
  }

  /** Changes are allowed before the visit is under way. */
  protected editable(appt: Appointment): boolean {
    return ['scheduled', 'checked_in'].includes(appt.status);
  }

  protected depositSummary(appt: Appointment): string {
    const d = appt.deposit;
    if (!d) return 'None taken';
    const money = `$${(d.amount_cents / 100).toFixed(2)}`;
    return d.status === 'held' ? `${money} held` : `${money} · ${humanise(d.status)}`;
  }

  protected onSectionToggle(section: PanelSection, event: Event): void {
    const open = (event.target as HTMLDetailsElement).open;
    if (open) this.openSection.set(section);
    else if (this.openSection() === section) this.openSection.set(null);
  }

  /** From the ⋮ menu: unfold the right section and put the cursor in it. */
  protected openEditor(section: PanelSection, testId: string): void {
    this.openSection.set(section);
    this.focusEditor(testId);
  }

  protected closeMenu(event: Event): void {
    if ((event.target as HTMLElement).closest('button')) {
      (event.currentTarget as HTMLElement).closest('details')?.removeAttribute('open');
    }
  }

  protected preferenceFacts(appt: Appointment): Fact[] {
    const p = appt.preference;
    if (!p) return [];
    return (
      [
        { label: 'Pressure', value: p.pressure ? humanise(p.pressure) : null },
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

  /**
   * Hour and half-hour lines as a percentage of the open day — the same
   * arithmetic `placed()` uses, so a 13:00 block starts on the 13:00 line.
   */
  protected readonly ruler = computed<RulerMark[]>(() => {
    const b = this.board();
    if (!b) return [];
    const open = this.toMinutes(b.opens_at);
    const close = this.toMinutes(b.closes_at);
    const marks: RulerMark[] = [];
    for (let m = Math.ceil(open / 30) * 30; m <= close; m += 30) {
      marks.push({
        minutes: m,
        pct: ((m - open) / (close - open)) * 100,
        hour: m % 60 === 0,
        label: this.hhmm(m),
      });
    }
    return marks;
  });

  ngOnInit(): void {
    // Deep links from the dashboard: `?date=` opens that day, `?appt=` opens that appointment.
    const query = this.route.snapshot.queryParamMap;
    void this.ctx.load().then(() => {
      this.date ||= query.get('date') || todayIn(this.ctx.current()?.timezone);
      this.loadEditors();
      this.reload();
      const appointmentId = Number(query.get('appt'));
      if (appointmentId) {
        this.api.appointment(appointmentId).subscribe({
          next: (full) => this.select(full),
          error: () => this.error.set('That appointment could not be opened.'),
        });
      }
    });
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.loading.set(true);
    this.error.set(null);
    this.loadOnShift();
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

  protected async refundDeposit(appointment: Appointment): Promise<void> {
    const amount = ((appointment.deposit?.amount_cents ?? 0) / 100).toFixed(2);
    const ok = await this.confirm.confirm({
      title: `Record $${amount} deposit as given back?`,
      message: `Do this once the money has actually been returned to ${appointment.client.full_name}. The deposit will no longer come off the bill at checkout.`,
      confirmLabel: 'Deposit given back',
      tone: 'danger',
    });
    if (!ok) return;
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
    const lane = (event.currentTarget as HTMLElement).closest<HTMLElement>('[data-lane-room]');
    this.drag = {
      appointment,
      startX: event.clientX,
      startY: event.clientY,
      laneWidth: lane?.getBoundingClientRect().width ?? 0,
      moved: false,
    };
  }

  @HostListener('document:pointermove', ['$event'])
  protected pointerMove(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag) return;
    // A small wobble is still a tap.
    if (!drag.moved && Math.hypot(event.clientX - drag.startX, event.clientY - drag.startY) < 8) {
      return;
    }
    drag.moved = true;
    this.dragging.set(drag.appointment.id);
    this.preview.set(this.previewAt(drag, event));
  }

  @HostListener('document:pointerup', ['$event'])
  protected pointerUp(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag) {
      // Released after Escape cancelled the drag: that release is not a click either.
      if (this.suppressClick) setTimeout(() => (this.suppressClick = false));
      return;
    }
    const preview = drag.moved ? this.previewAt(drag, event) : null;
    this.endDrag();
    if (!drag.moved) return;

    this.suppressClick = true;
    setTimeout(() => (this.suppressClick = false));
    // Released outside the rooms, or back where it started: nothing moves.
    if (!preview?.changed) return;
    this.moveAppointment(
      drag.appointment,
      this.localIso(drag.appointment, this.date, this.hhmm(preview.start)),
      preview.roomId,
    );
  }

  @HostListener('document:pointercancel')
  protected pointerCancel(): void {
    this.endDrag();
  }

  @HostListener('document:keydown.escape')
  protected cancelDrag(): void {
    if (!this.drag?.moved) return;
    this.endDrag();
    this.suppressClick = true;
  }

  private endDrag(): void {
    this.drag = null;
    this.dragging.set(null);
    this.preview.set(null);
  }

  /**
   * Where the block lands if released now. Its left edge follows the pointer
   * (so grabbing the middle of a block does not shift it), snapped to 15
   * minutes and kept inside opening hours, in the room under the pointer.
   */
  private previewAt(drag: DragState, event: PointerEvent): DropPreview | null {
    const board = this.board();
    const lane = (document.elementsFromPoint?.(event.clientX, event.clientY) ?? []).find(
      (el): el is HTMLElement => el instanceof HTMLElement && !!el.dataset['laneRoom'],
    );
    const room = board?.rooms.find((r) => String(r.id) === lane?.dataset['laneRoom']);
    if (!board || !room || !drag.laneWidth) return null;

    const appt = drag.appointment;
    const open = this.toMinutes(board.opens_at);
    const close = this.toMinutes(board.closes_at);
    const span = close - open;
    const from = this.minutesOfDay(appt.starts_at);
    const length = this.minutesOfDay(appt.service_ends_at) - from;
    const raw = from + ((event.clientX - drag.startX) / drag.laneWidth) * span;
    const latest = close - length - 15;
    const start = Math.max(open, Math.min(Math.round(raw / 15) * 15, latest));
    return {
      roomId: room.id,
      roomName: room.name,
      start,
      leftPct: ((start - open) / span) * 100,
      widthPct: (length / span) * 100,
      label: `${this.hhmm(start)}–${this.hhmm(start + length)}`,
      changed: start !== from || room.id !== appt.room.id,
    };
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
    setTimeout(() =>
      document
        .querySelector('[data-testid="checkout-rating"]')
        ?.scrollIntoView({ block: 'center', behavior: 'smooth' }),
    );
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
      const el = document.querySelector(`[data-testid="${testId}"]`) as HTMLElement | null;
      el?.scrollIntoView({ block: 'center', behavior: 'smooth' });
      el?.focus({ preventScroll: true });
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
    // A different appointment starts folded; the same one, just saved, stays where the desk was.
    if (this.selected()?.id !== appointment.id) this.openSection.set(null);
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

  /** Therapists rostered on the board's day — the only people an appointment can be given to. */
  private loadOnShift(): void {
    const loc = this.ctx.current();
    if (!loc || !this.date) return;
    this.api.shifts(loc.id, this.date).subscribe({
      next: ({ working }) => {
        const onShift = new Map<number, StaffMember>();
        for (const w of working) {
          onShift.set(w.staff_profile_id, {
            id: w.staff_profile_id,
            display_name: w.display_name,
          } as StaffMember);
        }
        this.staff.set(
          [...onShift.values()].sort((a, b) => a.display_name.localeCompare(b.display_name)),
        );
      },
      error: () => this.staff.set([]),
    });
  }

  private loadEditors(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.services(loc.id).subscribe(({ services }) => this.services.set(services));
  }

  private apiMessage(err: any, fallback: string): string {
    const body = err?.error?.error;
    if (typeof body === 'string') return MESSAGES[body] ?? body;
    return (body?.code && MESSAGES[body.code]) || body?.message || body?.code || fallback;
  }

  private hhmm(minutes: number): string {
    return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
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
