import { ChipTone } from './chip';

/**
 * One mapping from a domain status to a colour, so "cancelled" is never red on
 * one screen and grey on another. Anything unknown stays neutral rather than
 * guessing.
 */
const TONES: Record<string, ChipTone> = {
  completed: 'success',
  published: 'success',
  active: 'success',
  settled: 'success',
  approved: 'success',

  scheduled: 'info',
  checked_in: 'info',
  in_progress: 'info',
  open: 'info',
  submitted: 'info',

  pending_approval: 'warning',
  draft: 'warning',
  expiring: 'warning',

  cancelled: 'error',
  late_cancelled: 'error',
  no_show: 'error',
  rejected: 'error',
  voided: 'error',
  terminated: 'error',
};

export function statusTone(status: string | null | undefined): ChipTone {
  return TONES[String(status)] ?? 'neutral';
}

/** `late_cancelled` reads as "Late cancelled", not as a database value. */
export function humanise(value: string | null | undefined): string {
  if (!value) return '';
  const s = String(value).replace(/_/g, ' ');
  return s.charAt(0).toUpperCase() + s.slice(1);
}
