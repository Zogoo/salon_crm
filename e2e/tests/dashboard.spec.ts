import { expect, test } from '@playwright/test';

import { USERS, book, nextBusinessDate, signIn } from './support';

// The dashboard summarises; each number and short list opens the screen that owns the detail.
test.describe('Dashboard', () => {
  const date = nextBusinessDate();

  test.beforeEach(async ({ page }) => {
    await signIn(page, USERS.manager);
  });

  test('previews the day and opens an appointment in one tap', async ({ page }) => {
    const id = await book(page, { client: 'Emily Rodriguez', date });

    await page.goto('/dashboard');
    await page.getByTestId('dash-date').fill(date);
    await page.getByTestId('dash-date').dispatchEvent('change');

    // A preview, never the whole list.
    const next = page.getByTestId('dash-next');
    await expect(next.locator('.preview__row')).not.toHaveCount(0);
    expect(await next.locator('.preview__row').count()).toBeLessThanOrEqual(5);
    const team = page.getByTestId('dash-team');
    expect(await team.locator('.preview__row').count()).toBeLessThanOrEqual(5);

    await page.getByTestId(`next-${id}`).click();
    await expect(page).toHaveURL(new RegExp(`/schedule\\?date=${date}&appt=${id}`));
    await expect(page.getByTestId('appointment-panel')).toBeVisible();
  });

  test('a tile opens its list already filtered to the day', async ({ page }) => {
    await page.getByTestId('dash-date').fill(date);
    await page.getByTestId('dash-date').dispatchEvent('change');

    await page.getByTestId('tile-staff').getByRole('link').click();
    await expect(page).toHaveURL(new RegExp(`/admin/roster\\?from=${date}&to=${date}`));
    await expect(page.getByTestId('roster-from')).toHaveValue(date);
  });
});
