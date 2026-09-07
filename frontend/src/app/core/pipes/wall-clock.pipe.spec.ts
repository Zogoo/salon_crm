import { describe, expect, it } from 'vitest';

import { WallClockPipe } from './wall-clock.pipe';

describe('WallClockPipe', () => {
  const pipe = new WallClockPipe();

  // The bug this exists to prevent: a 09:00 Chicago booking rendered as 14:00
  // because DatePipe converted it into the viewer's timezone.
  it('keeps the salon wall clock regardless of the viewer timezone', () => {
    expect(pipe.transform('2026-09-07T09:00:00-05:00')).toBe('09:00');
    expect(pipe.transform('2026-09-07T09:00:00Z')).toBe('09:00');
    expect(pipe.transform('2026-09-07T21:45:00-05:00')).toBe('21:45');
  });

  it('formats dates and datetimes without a Date conversion', () => {
    expect(pipe.transform('2026-09-07T09:00:00-05:00', 'date')).toBe('Mon 7 Sep 2026');
    expect(pipe.transform('2026-09-07T09:00:00-05:00', 'datetime')).toBe('Mon 7 Sep 2026 09:00');
  });

  it('passes through empty and unparseable input', () => {
    expect(pipe.transform(null)).toBe('');
    expect(pipe.transform(undefined)).toBe('');
    expect(pipe.transform('not-a-date')).toBe('not-a-date');
  });
});
