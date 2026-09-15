import { expect, test } from '@playwright/test';

import { USERS, signIn } from './support';

// The Owner's tools that the feedback round added or changed.
test.describe('Owner tools', () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page, USERS.owner);
  });

  test('sets the Manager discount limit per location', async ({ page }) => {
    await page.goto('/admin/location');
    const limit = page.getByTestId('location-discount-limit');
    await expect(limit).toBeVisible();

    await limit.fill('30');
    await page.getByTestId('location-save').click();
    await expect(page.getByTestId('loc-notice')).toBeVisible();
    await page.reload();
    await expect(page.getByTestId('location-discount-limit')).toHaveValue('30');

    // Put it back, so the desk tests keep the seeded 20% whatever the order.
    await page.getByTestId('location-discount-limit').fill('20');
    await page.getByTestId('location-save').click();
    await expect(page.getByTestId('loc-notice')).toBeVisible();
  });

  test('sells a gift card with a chosen code and explains a duplicate code', async ({ page }) => {
    const code = `E2E-${Date.now()}`;
    const sell = async () => {
      await page.getByTestId('gc-new-code').fill(code);
      await page.getByTestId('gc-new-amount').fill('50');
      await page.getByTestId('gc-buyer').fill('E2E Buyer');
      await page.getByTestId('gc-buyer-phone').fill('+13125550199');
      await page.getByTestId('gc-issue').click();
    };

    await page.goto('/gift-cards');
    await sell();
    await expect(page.getByTestId('gc-issued')).toContainText(code);

    await sell();
    await expect(page.getByTestId('gc-error')).toContainText('already in use');
  });

  test('reads the audit trail', async ({ page }) => {
    await page.goto('/admin/audit-log');
    // Let the unfiltered first load finish; Search is disabled while it runs.
    await expect(page.getByTestId('audit-table')).toBeVisible();

    await page.getByTestId('audit-action').fill('gift_card');
    const searched = page.waitForResponse((r) => r.url().includes('audit_action=gift_card'));
    await page.getByTestId('audit-search').click();
    const body = await (await searched).json();

    expect(body.audit_logs.length).toBeGreaterThan(0);
    expect(body.audit_logs.every((l: { action: string }) => l.action.includes('gift_card'))).toBe(true);
    await expect(page.getByTestId('audit-table')).toContainText('gift_card.issued');
  });

  test('sees discounts and held deposits beside revenue, not inside it', async ({ page }) => {
    await page.goto('/reports');
    await page.getByTestId('rep-run').click();
    await expect(page.getByTestId('rep-revenue')).toBeVisible();
    await expect(page.getByTestId('rev-discounts')).toBeVisible();
    await expect(page.getByTestId('rev-deposits-held')).toBeVisible();
  });

  test('adds an earnings amount without inventing a session (feedback 5.1)', async ({ page }) => {
    await page.goto('/earnings');
    const staff = page.getByTestId('earn-staff');
    await expect(staff.locator('option').nth(1)).toBeAttached();
    await staff.selectOption({ index: 1 });
    // Manual entry sits under the therapist's report, so run it first.
    await page.getByTestId('earn-run').click();
    await expect(page.getByTestId('earn-table')).toBeVisible();

    await page.getByTestId('manual-amount').fill('12.50');
    await page.getByTestId('manual-note').fill('E2E correction');
    const added = page.waitForResponse(
      (r) => r.url().endsWith('/api/v1/earning_lines') && r.request().method() === 'POST',
    );
    await page.getByTestId('manual-add').click();

    const response = await added;
    expect(response.status(), await response.text()).toBe(201);
    const body = await response.json();
    expect(body.amount_cents).toBe(1250);
    expect(body.duration_minutes).toBeNull();
  });
});
