import { expect, test } from '@playwright/test';

import { USERS, signIn } from './support';

// The therapist's own screens: their day, and asking for a change.
test.describe('Therapist', () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page, USERS.therapist);
  });

  test("sees their own day on the dashboard, not the salon's occupancy", async ({ page }) => {
    await expect(page.getByTestId('my-shift')).toBeVisible();
    await expect(page.getByTestId('dash-tiles')).toHaveCount(0);
    await expect(page.locator('body')).not.toContainText('Draft and publish shifts');
  });

  test('asks for a shift change by picking a shift, never typing an id', async ({ page }) => {
    await page.goto('/staff-requests');
    await expect(page.locator('body')).not.toContainText('Shift ID');

    const shift = page.getByTestId('request-shift');
    await expect(shift.locator('option').nth(1)).toBeAttached();
    await shift.selectOption({ index: 1 });
    // Picking the shift starts the times from what it is now.
    await expect(page.getByTestId('request-start')).toHaveValue('09:00');
    await page.getByTestId('request-end').fill('18:00');
    await page.getByTestId('request-note').fill('Appointment after work');
    await page.getByTestId('staff-request-submit').click();

    await expect(page.getByTestId('staff-request-notice')).toBeVisible();
    const list = page.getByTestId('staff-request-list');
    await expect(list).toContainText('Shift change');
    await expect(list).toContainText('09:00–22:00 → 09:00–18:00');
  });

  test('asks to move by choosing a location by name', async ({ page }) => {
    await page.goto('/staff-requests');
    await page.getByTestId('request-kind').selectOption('location_change');
    await page.getByTestId('request-location').selectOption({ label: 'Luma' });
    await page.getByTestId('staff-request-submit').click();

    await expect(page.getByTestId('staff-request-list')).toContainText('Move to Luma');
  });
});
