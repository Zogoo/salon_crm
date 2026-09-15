import { expect, test } from '@playwright/test';

import { USERS, assignTherapist, book, nextBusinessDate, openOnBoard, signIn } from './support';

// The front desk's whole visit, end to end: book with no preference, assign,
// take a deposit, discount, rate, check out in one step, pay, settle.
test.describe('Front-desk visit', () => {
  const date = nextBusinessDate();

  test.beforeEach(async ({ page }) => {
    await signIn(page, USERS.manager);
  });

  test('deposit and discount come off the bill, and the order settles', async ({ page }) => {
    const id = await book(page, { client: 'Sarah Johnson', date });
    await openOnBoard(page, date, id);
    await assignTherapist(page);

    await page.getByTestId('deposit-amount').fill('20');
    await page.getByTestId('deposit-method').selectOption('zelle');
    await page.getByTestId('deposit-save').click();
    await expect(page.getByTestId('deposit-notice')).toContainText('$20.00');

    await page.getByTestId('appointment-discount-amount').fill('10');
    await page.getByTestId('appointment-discount-reason').fill('Started late');
    await page.getByTestId('appointment-discount-save').click();
    await expect(page.getByTestId('discount-notice')).toContainText('$10.00');

    await page.getByTestId('go-checkout').click();
    await page.getByTestId('rating-score-9').click();
    const completed = page.waitForResponse((r) => r.url().endsWith(`/appointments/${id}/complete_for_checkout`));
    await page.getByTestId('rating-continue').click();
    expect((await completed).status()).toBe(200);
    await expect(page).toHaveURL(new RegExp(`/checkout/${id}$`));

    await expect(page.getByTestId('order-total')).toContainText('$70.00');
    await expect(page.getByTestId('order-deposit')).toContainText('$20.00');
    await expect(page.getByTestId('order-outstanding')).toContainText('$50.00');

    await page.getByTestId('pay-remainder').click();
    await expect(page.getByTestId('order-outstanding')).toContainText('$0.00');
    await page.getByTestId('settle').click();
    await expect(page.getByTestId('checkout-done')).toBeVisible();
  });

  test('a Manager discount above the location limit is refused with a clear reason', async ({ page }) => {
    const id = await book(page, { client: 'Michael Chen', date });
    await openOnBoard(page, date, id);

    // Lawrence allows a Manager 20% of $80 = $16.
    await page.getByTestId('appointment-discount-amount').fill('50');
    await page.getByTestId('appointment-discount-reason').fill('Complaint');
    await page.getByTestId('appointment-discount-save').click();

    await expect(page.getByTestId('board-error')).toContainText('Ask the Owner');
    await expect(page.getByTestId('discount-notice')).toHaveCount(0);
  });
});
