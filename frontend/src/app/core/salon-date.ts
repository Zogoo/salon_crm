/**
 * Today's date in the salon's timezone, as YYYY-MM-DD.
 *
 * `new Date().toISOString().slice(0, 10)` gives the **UTC** date. The salon is
 * open until 22:00 Central, which is 03:00–04:00 UTC the next day, so every
 * screen defaulting to "today" that way shows tomorrow's board — and an empty
 * one — for the last few hours of every working day.
 *
 * Doc 03 §5: business rules expressed in local terms are evaluated in the
 * location's timezone, never the server's and never the browser's.
 */
export function todayIn(timezone: string | undefined | null): string {
  if (!timezone) return new Date().toISOString().slice(0, 10);
  // en-CA formats as YYYY-MM-DD, which is what date inputs expect.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}
