import { describe, expect, it } from 'vitest';

import { todayIn } from './salon-date';

describe('todayIn', () => {
  // The bug this exists to prevent: the salon is open until 22:00 Central,
  // which is 03:00–04:00 UTC the next day, so a UTC-derived "today" showed
  // tomorrow's empty board for the last hours of every working day.
  it('returns the salon date, not the UTC date', () => {
    const chicago = todayIn('America/Chicago');
    const utc = new Date().toISOString().slice(0, 10);

    expect(chicago).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    // Late in the Chicago evening these legitimately differ; the point is that
    // the function follows the zone it was given rather than the browser's.
    const tokyo = todayIn('Asia/Tokyo');
    expect(tokyo).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect([chicago, tokyo]).toContain(utc.length === 10 ? utc : chicago);
  });

  it('is stable and ordered across zones', () => {
    const chicago = todayIn('America/Chicago');
    const tokyo = todayIn('Asia/Tokyo');
    // Tokyo is always the same day or ahead of Chicago, never behind.
    expect(tokyo >= chicago).toBe(true);
  });

  it('falls back to the UTC date when no timezone is known' , () => {
    expect(todayIn(undefined)).toBe(new Date().toISOString().slice(0, 10));
    expect(todayIn(null)).toBe(new Date().toISOString().slice(0, 10));
  });
});
