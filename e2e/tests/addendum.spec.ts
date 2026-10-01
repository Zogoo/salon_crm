import { expect, test } from '@playwright/test';

import {
  USERS,
  assignTherapist,
  book,
  chooseService,
  nextBusinessDate,
  openOnBoard,
  signIn,
} from './support';

// The FRS addendum, as the desk and the Owner use it in the browser.
test.describe('FRS addendum', () => {
  const date = nextBusinessDate();

  test('§1 §2 §5 — a split payment with a fee, then the closed visit is corrected', async ({
    page,
  }) => {
    await signIn(page, USERS.manager);

    // A $70 gift card to pay part of the bill with.
    const code = `E2E-SPLIT-${Date.now()}`;
    await page.goto('/gift-cards');
    await page.getByTestId('gc-new').click();
    await page.getByTestId('gc-new-code').fill(code);
    await page.getByTestId('gc-new-amount').fill('70');
    await page.getByTestId('gc-issue').click();
    await expect(page.getByTestId('gc-issued')).toContainText(code);

    const id = await book(page, { client: 'Jessica Brown', date });
    await openOnBoard(page, date, id);
    await assignTherapist(page);
    await page.getByTestId('go-checkout').click();
    await page.getByTestId('rating-declined').click();
    await expect(page).toHaveURL(new RegExp(`/checkout/${id}$`));

    // $80 service + $20 tip + $5 transaction fee = $105.
    await page.getByTestId('tip-amount').fill('20');
    await page.getByTestId('tip-apply').click();
    await page.getByTestId('fee-amount').fill('5');
    await page.getByTestId('fee-apply').click();
    await expect(page.getByTestId('order-fee-line')).toContainText('$5.00');
    await expect(page.getByTestId('order-total')).toContainText('$105.00');

    await page.getByTestId('pay-split').click();
    await page.getByTestId('pay-method-0').selectOption('gift_card');
    await page.getByTestId('pay-code-0').fill(code);
    await page.getByTestId('pay-amount-0').fill('70');
    // The second part fills itself in with what is left.
    await expect(page.getByTestId('pay-amount-1')).toHaveValue('35');
    await page.getByTestId('pay-method-1').selectOption('venmo');
    await page.getByTestId('pay-amount-1').fill('30');
    await expect(page.getByTestId('pay-split-check')).toContainText('$5.00 still to assign');
    await expect(page.getByTestId('pay-and-close').getByRole('button')).toBeDisabled();
    await page.getByTestId('pay-amount-1').fill('35');
    await expect(page.getByTestId('pay-split-check')).toContainText('Adds up to $105.00');
    await page.getByTestId('pay-and-close').click();
    await expect(page.getByTestId('checkout-done')).toBeVisible();

    // §2: the tip was really $25, and the rest was cash.
    await openOnBoard(page, date, id);
    await page.getByTestId('visit-correct').click();
    const dialog = page.getByTestId('visit-correction');
    await expect(dialog.getByTestId('correction-tip')).toHaveValue('20');
    await dialog.getByTestId('correction-tip').fill('25');
    await dialog.getByTestId('pay-method-0').selectOption('cash');
    await dialog.getByTestId('pay-amount-0').fill('40');
    await expect(dialog.getByTestId('pay-split-check')).toContainText('Adds up to $110.00');
    await dialog.getByTestId('correction-reason').fill('Tip keyed wrong; paid cash');
    const corrected = page.waitForResponse((r) =>
      r.url().endsWith(`/appointments/${id}/correct_visit`),
    );
    await dialog.getByTestId('correction-save').click();
    expect((await corrected).status()).toBe(200);
    await expect(dialog).toHaveCount(0);

    await page.goto(`/checkout/${id}`);
    await expect(page.getByTestId('order-total')).toContainText('$110.00');
    await expect(page.getByTestId('taken-list')).toContainText('Cash');
  });

  test('§6 — a named-therapist booking is approved from the schedule', async ({ page }) => {
    await signIn(page, USERS.manager);
    await page.goto('/book');
    await page.getByTestId('client-picker-input').fill('Emily Rodriguez');
    await page
      .getByTestId('client-picker-results')
      .getByRole('option', { name: /Emily Rodriguez/ })
      .first()
      .click();
    await chooseService(page, 'Deep Tissue', '60 min');
    await page.getByTestId('booking-date').fill(date);
    const therapist = page.getByTestId('therapist-select');
    await expect(therapist.locator('option').nth(1)).toBeAttached();
    await therapist.selectOption({ index: 1 });
    await page.getByTestId('search-slots').click();
    await page.getByTestId('slots').locator('button').last().click();
    const created = page.waitForResponse(
      (r) => r.url().endsWith('/api/v1/appointments') && r.request().method() === 'POST',
    );
    await page.getByTestId('confirm-booking').click();
    const id = (await (await created).json()).id as number;

    await openOnBoard(page, date, id);
    await expect(page.getByTestId('approval-callout')).toContainText('asked for');
    await page.getByTestId('approval-approve').click();
    await expect(page.getByTestId('approval-callout')).toHaveCount(0);
    await expect(page.getByTestId(`appt-${id}`)).toHaveAttribute('data-status', 'scheduled');
  });

  test('§7 — a couples booking saves with only the first client', async ({ page }) => {
    await signIn(page, USERS.manager);
    await page.goto('/book');
    await chooseService(page, 'Couples massage', '60 min');
    // A couples service offers a second search for the other client; the first is the booker.
    await page.getByRole('combobox', { name: 'Find a client' }).fill('Michael Chen');
    await page
      .getByTestId('client-picker-results')
      .getByRole('option', { name: /Michael Chen/ })
      .first()
      .click();
    await expect(page.getByTestId('second-client')).toContainText('optional');
    await page.getByTestId('booking-date').fill(date);
    await page.getByTestId('search-slots').click();
    await page.getByTestId('slots').locator('button').first().click();
    await page.getByTestId('confirm-booking').click();
    await expect(page.getByTestId('booking-success')).toBeVisible();
  });

  test('§8 — a Manager sets a therapist’s working hours from the Staff section', async ({
    page,
  }) => {
    await signIn(page, USERS.manager);
    await page.goto('/admin/staff');
    await expect(page.getByTestId('staff-new')).toHaveCount(0);
    await page.locator('a.dt__row--link').first().click();
    await expect(page.getByTestId('staff-tab-pay')).toHaveCount(0);
    await page.getByTestId('staff-tab-hours').click();

    // A weekday away from the one the other tests book on.
    const weekday = (new Date(`${date}T12:00:00Z`).getUTCDay() + 3) % 7 || 1;
    await page.getByTestId(`hours-mode-${weekday}`).selectOption('working');
    await page.getByTestId(`hours-start-${weekday}`).fill('10:00');
    await page.getByTestId(`hours-end-${weekday}`).fill('18:00');
    await page.getByTestId('hours-save').click();
    await expect(page.getByTestId('staff-notice')).toContainText('Working hours saved');

    await page.reload();
    await page.getByTestId('staff-tab-hours').click();
    await expect(page.getByTestId(`hours-start-${weekday}`)).toHaveValue('10:00');
  });

  test('§3 §4 — the Owner reads total revenue and corrects a session count', async ({ page }) => {
    await signIn(page, USERS.owner);
    await page.goto('/reports');
    await expect(page.getByTestId('rev-total')).toContainText('total revenue');
    await page.getByTestId('rep-period-month').click();
    await expect(page.getByTestId('rep-range')).toContainText('–');
    await page.getByTestId('rep-scope').selectOption('all');
    await expect(page.getByTestId('rev-by-location')).toBeVisible();

    await page.goto('/earnings');
    await page.getByTestId('staff-picker-input').click();
    await page.getByTestId('staff-picker-results').locator('[role=option]').first().click();
    await page.getByTestId('earn-run').click();
    const qty = page.getByTestId('earn-qty-60');
    const before = Number(await qty.inputValue());
    await qty.fill(String(before + 2));
    await qty.press('Enter');
    await expect(page.getByTestId('earn-qty-notice')).toContainText(
      `changed from ${before} to ${before + 2}`,
    );
    await expect(qty).toHaveValue(String(before + 2));
  });
});
