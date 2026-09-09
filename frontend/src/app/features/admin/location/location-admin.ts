import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { BusinessHour, Closure, Room, RoomBlock } from '../../../core/models';
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
  UiSheet,
  UiTable,
  humanise,
  statusTone,
} from '../../../ui';

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/**
 * Doc 02 §3.2 — hours, closures, rooms and room blocks.
 *
 * All four feed the availability engine directly: a closure empties the day
 * (C1), a block takes a room out exactly as an appointment would, and a room's
 * capacity and type decide what can be booked into it. Each edit is refused if
 * it would strand an appointment already on the books.
 */
@Component({
  selector: 'app-location-admin',
  imports: [
    FormsModule,
    UiPage,
    UiCard,
    UiField,
    UiButton,
    UiChip,
    UiEmpty,
    UiTable,
    UiBanner,
    UiSheet,
  ],
  templateUrl: './location-admin.html',
  styleUrl: '../admin-shared.scss',
})
export class LocationAdminPage implements OnInit {
  private readonly api = inject(MassagelabService);
  protected readonly ctx = inject(LocationContextService);

  protected readonly hours = signal<BusinessHour[]>([]);
  protected readonly closures = signal<Closure[]>([]);
  protected readonly rooms = signal<Room[]>([]);
  protected readonly blocks = signal<RoomBlock[]>([]);
  protected readonly blockedRoom = signal<Room | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly notice = signal<string | null>(null);

  protected readonly days = DAYS;

  protected tone(status: string | undefined) { return statusTone(status); }
  protected humanStatus(value: string | undefined) { return humanise(value); }

  protected newHour = { day_of_week: 1, opens_at: '09:00', closes_at: '22:00' };
  protected newClosure = { date: '', reason: '' };
  protected newRoom = { name: '', room_type: 'single', client_capacity: 1, position: 0 };
  protected newBlock = { date: '', starts_at: '09:00', ends_at: '12:00', reason: '' };

  ngOnInit(): void {
    void this.ctx.load().then(() => {
      const today = todayIn(this.ctx.current()?.timezone);
      this.newClosure.date = today;
      this.newBlock.date = today;
      this.reload();
    });
  }

  protected onLocationChange(id: number): void {
    this.ctx.select(id);
    this.blockedRoom.set(null);
    this.reload();
  }

  protected reload(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.api.businessHours(loc.id).subscribe({
      next: ({ business_hours }) => this.hours.set(business_hours),
      error: () => this.hours.set([]),
    });
    this.api.closures(loc.id).subscribe({
      next: ({ closures }) => this.closures.set(closures),
      error: () => this.closures.set([]),
    });
    this.api.locationRooms(loc.id).subscribe({
      next: ({ rooms }) => this.rooms.set(rooms),
      error: () => this.rooms.set([]),
    });
  }

  protected dayName(dow: number): string {
    return DAYS[dow] ?? String(dow);
  }

  // --- hours ---

  protected addHour(): void {
    this.hours.update((rows) => [...rows, { ...this.newHour }]);
  }

  protected removeHour(index: number): void {
    this.hours.update((rows) => rows.filter((_, i) => i !== index));
  }

  protected saveHours(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.clear();

    this.api.setBusinessHours(loc.id, this.hours()).subscribe({
      next: ({ business_hours }) => {
        this.hours.set(business_hours);
        this.notice.set('Hours saved.');
      },
      error: (err) => this.error.set(this.message(err, 'Could not save hours')),
    });
  }

  // --- closures (C1) ---

  protected addClosure(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.clear();

    this.api.createClosure(loc.id, this.newClosure.date, this.newClosure.reason).subscribe({
      next: () => {
        this.notice.set('Closed. That day now offers no times at all.');
        this.newClosure.reason = '';
        this.reload();
      },
      error: (err) => this.error.set(this.strandedMessage(err, 'Could not close that day')),
    });
  }

  protected removeClosure(closure: Closure): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.clear();

    this.api.deleteClosure(loc.id, closure.id).subscribe({
      next: () => {
        this.notice.set('Reopened.');
        this.reload();
      },
      error: (err) => this.error.set(this.message(err, 'Could not reopen that day')),
    });
  }

  // --- rooms and blocks ---

  protected addRoom(): void {
    const loc = this.ctx.current();
    if (!loc) return;
    this.clear();

    this.api.createRoom(loc.id, this.newRoom).subscribe({
      next: () => {
        this.notice.set('Room added.');
        this.newRoom.name = '';
        this.reload();
      },
      error: (err) => this.error.set(this.message(err, 'Could not add that room')),
    });
  }

  protected showBlocks(room: Room): void {
    this.clear();
    this.blockedRoom.set(room);
    this.api.roomBlocks(room.id).subscribe({
      next: ({ blocks }) => this.blocks.set(blocks),
      error: () => this.blocks.set([]),
    });
  }

  protected addBlock(): void {
    const room = this.blockedRoom();
    if (!room) return;
    this.clear();

    // The API takes instants; the salon's own offset is applied server-side
    // from the location's zone.
    const starts = `${this.newBlock.date}T${this.newBlock.starts_at}`;
    const ends = `${this.newBlock.date}T${this.newBlock.ends_at}`;

    this.api.createRoomBlock(room.id, starts, ends, this.newBlock.reason).subscribe({
      next: () => {
        this.notice.set('Room blocked for that window.');
        this.newBlock.reason = '';
        this.showBlocks(room);
      },
      error: (err) => this.error.set(this.strandedMessage(err, 'Could not block that room')),
    });
  }

  protected removeBlock(block: RoomBlock): void {
    const room = this.blockedRoom();
    if (!room) return;
    this.clear();

    this.api.deleteRoomBlock(room.id, block.id).subscribe({
      next: () => this.showBlocks(room),
      error: (err) => this.error.set(this.message(err, 'Could not remove that block')),
    });
  }

  protected wallClock(iso: string): string {
    return `${iso.slice(0, 10)} ${iso.slice(11, 16)}`;
  }

  private clear(): void {
    this.error.set(null);
    this.notice.set(null);
  }

  /** Closures and blocks refuse to strand appointments already booked. */
  private strandedMessage(err: unknown, fallback: string): string {
    const e = err as { error?: { error?: { details?: { appointment_ids?: number[] } } } };
    const ids = e?.error?.error?.details?.appointment_ids;
    if (ids?.length) {
      return `Appointment(s) ${ids.join(', ')} are booked in that window. Move them first.`;
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
