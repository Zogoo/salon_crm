import { Pipe, PipeTransform } from '@angular/core';

const ISO = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/**
 * Renders an instant in the *salon's* wall clock, not the viewer's.
 *
 * Doc 03 §5: business rules are expressed in the location's timezone, and the
 * API already returns ISO 8601 with that location's offset — so the wall clock
 * in the string is the salon time. Angular's DatePipe would convert it into
 * whatever zone the browser happens to be in, which shows a Chicago manager the
 * wrong hour whenever their machine is set elsewhere.
 */
@Pipe({ name: 'wallClock' })
export class WallClockPipe implements PipeTransform {
  transform(iso: string | null | undefined, format: 'time' | 'date' | 'datetime' = 'time'): string {
    if (!iso) return '';
    const m = ISO.exec(iso);
    if (!m) return iso;

    const [, y, mo, d, h, min] = m;
    const time = `${h}:${min}`;
    if (format === 'time') return time;

    // Built from the parts, so no Date object and no zone conversion.
    const weekday = DAYS[new Date(Date.UTC(+y, +mo - 1, +d)).getUTCDay()];
    const date = `${weekday} ${Number(d)} ${MONTHS[+mo - 1]} ${y}`;
    return format === 'date' ? date : `${date} ${time}`;
  }
}
