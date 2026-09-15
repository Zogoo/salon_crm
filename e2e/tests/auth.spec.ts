import { expect, test } from '@playwright/test';

import { PASSWORD, USERS, signIn } from './support';

test.describe('Signing in and role boundaries', () => {
  test('the app is healthy and deep links load the console', async ({ page, request }) => {
    expect((await request.get('/up')).status()).toBe(200);
    await page.goto('/schedule');
    await expect(page).toHaveURL(/\/sign-in/);
  });

  test('a wrong password keeps the user out', async ({ page }) => {
    await page.goto('/sign-in');
    await page.getByTestId('email').fill(USERS.manager);
    await page.getByTestId('password').fill(`${PASSWORD}-wrong`);
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();

    await expect(page.locator('ui-banner')).toBeVisible();
    await expect(page).toHaveURL(/\/sign-in/);
  });

  test('the Owner reaches the money reports', async ({ page }) => {
    await signIn(page, USERS.owner);
    await expect(page.getByTestId('current-role')).toHaveText('owner');
    await page.goto('/reports');
    await expect(page).toHaveURL(/\/reports/);
    await expect(page.getByTestId('rep-run')).toBeVisible();
  });

  test('a Manager books but cannot open Owner-only screens (BR-02)', async ({ page }) => {
    await signIn(page, USERS.manager);
    await page.goto('/book');
    await expect(page.getByTestId('service-select')).toBeVisible();

    for (const path of ['/reports', '/earnings', '/admin/audit-log']) {
      await page.goto(path);
      await expect(page).toHaveURL(/\/dashboard/);
    }
  });

  test('a therapist can neither book nor see money (BR-14)', async ({ page }) => {
    await signIn(page, USERS.therapist);
    await expect(page.getByTestId('current-role')).toHaveText('staff');

    for (const path of ['/book', '/reports', '/gift-cards']) {
      await page.goto(path);
      await expect(page).not.toHaveURL(new RegExp(path));
    }
  });
});
