import { Page, expect } from '@playwright/test';

/** Seeded by db/seeds (password kept deliberately for the review environment). */
export const PASSWORD = 'password123';
export const USERS = {
  owner: 'owner@mongolianmassagelab.com',
  manager: 'manager.lawrence@mongolianmassagelab.com',
  therapist: 'anna.lawrence@mongolianmassagelab.com',
} as const;

export async function signIn(page: Page, email: string): Promise<void> {
  await page.goto('/sign-in');
  await page.getByTestId('email').fill(email);
  await page.getByTestId('password').fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page).toHaveURL(/\/dashboard/);
  await expect(page.getByTestId('current-user')).toBeVisible();
}

/**
 * The next day the salon is open with a seeded roster: tomorrow in Chicago,
 * skipping Sunday (the seeds publish no Sunday shifts). Tomorrow rather than
 * today, so a run late in the evening still has open slots.
 */
export function nextBusinessDate(): string {
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Chicago' }).format(new Date());
  const d = new Date(`${today}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  if (d.getUTCDay() === 0) d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

/** Picks a length of a service from the grouped <select> on the booking page. */
async function chooseService(page: Page, service: string, length: string): Promise<void> {
  const select = page.getByTestId('service-select');
  await expect(select.locator('optgroup').first()).toBeAttached();
  const value = await select.evaluate(
    (el: HTMLSelectElement, [group, minutes]) => {
      const optgroup = Array.from(el.querySelectorAll('optgroup')).find((g) =>
        g.label.startsWith(group),
      );
      const option = optgroup
        ? Array.from(optgroup.querySelectorAll('option')).find((o) =>
            (o.textContent ?? '').trim().startsWith(minutes),
          )
        : undefined;
      return option?.value ?? null;
    },
    [service, length] as const,
  );
  expect(value, `${service} · ${length} is on the menu`).not.toBeNull();
  await select.selectOption(value!);
}

/**
 * Books a 60-minute Deep Tissue massage through the booking screen with no
 * therapist preference, and returns the new appointment's id.
 */
export async function book(
  page: Page,
  opts: { client: string; date: string; slot?: 'first' | 'last' },
): Promise<number> {
  await page.goto('/book');
  await page.getByTestId('client-search').fill(opts.client.split(' ')[0]);
  await page
    .getByTestId('client-select')
    .getByRole('button', { name: new RegExp(opts.client) })
    .click();
  await chooseService(page, 'Deep Tissue', '60 min');
  await page.getByTestId('booking-date').fill(opts.date);
  await page.getByTestId('search-slots').click();

  const slots = page.getByTestId('slots').locator('button');
  await expect(slots.first()).toBeVisible();
  await (opts.slot === 'last' ? slots.last() : slots.first()).click();

  const created = page.waitForResponse(
    (r) => r.url().endsWith('/api/v1/appointments') && r.request().method() === 'POST',
  );
  await page.getByTestId('confirm-booking').click();
  const response = await created;
  expect(response.status(), await response.text()).toBe(201);
  await expect(page.getByTestId('booking-success')).toBeVisible();
  return (await response.json()).id as number;
}

/** Opens the day board on a date. */
export async function showBoard(page: Page, date: string): Promise<void> {
  await page.goto('/schedule');
  const dateInput = page.getByTestId('date-input');
  await expect(dateInput).toHaveValue(/\d{4}-\d{2}-\d{2}/);
  await dateInput.fill(date);
  await dateInput.dispatchEvent('change');
}

/** Opens the day board on a date and the appointment's panel. */
export async function openOnBoard(page: Page, date: string, id: number): Promise<void> {
  await showBoard(page, date);
  await page.getByTestId(`appt-${id}`).click();
  await expect(page.getByTestId('appointment-panel')).toBeVisible();
}

/**
 * Confirms a therapist for a no-preference booking. Tries each therapist in
 * turn, because an earlier test may already have booked the first one then.
 */
export async function assignTherapist(page: Page): Promise<void> {
  const editor = page.getByTestId('assignment-editor');
  const boxes = editor.locator('input[type=checkbox]');
  await expect(boxes.first()).toBeVisible();
  const count = await boxes.count();

  for (let i = 0; i < count; i++) {
    for (let j = 0; j < count; j++) {
      if (await boxes.nth(j).isChecked()) await boxes.nth(j).uncheck();
    }
    await boxes.nth(i).check();
    const saved = page.waitForResponse((r) => r.url().includes('/assign_staff'));
    await page.getByTestId('assignment-save').click();
    if ((await saved).ok()) {
      await expect(editor).toBeHidden();
      return;
    }
  }
  throw new Error('No therapist could be assigned');
}

export async function openMenuAction(page: Page, action: string): Promise<void> {
  await page.getByTestId('appointment-menu').locator('summary').click();
  await page.getByTestId(`menu-${action}`).click();
}
