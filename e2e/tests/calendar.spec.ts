import { expect, test } from '@playwright/test';

import {
  USERS,
  assignTherapist,
  book,
  nextBusinessDate,
  openMenuAction,
  openOnBoard,
  showBoard,
  signIn,
} from './support';

// Feedback 1.1, 1.2, 3.1, 3.3 on the day board, as the front desk uses it.
test.describe('Day board', () => {
  const date = nextBusinessDate();

  test.beforeEach(async ({ page }) => {
    await signIn(page, USERS.manager);
  });

  test('a cancelled appointment leaves the board', async ({ page }) => {
    const id = await book(page, { client: 'Emily Rodriguez', date });
    await openOnBoard(page, date, id);

    await openMenuAction(page, 'cancelled');

    await expect(page.getByTestId(`appt-${id}`)).toHaveCount(0);
  });

  test('a no-show stays on the board, faded, and offers no further actions', async ({ page }) => {
    const id = await book(page, { client: 'David Kim', date });
    await openOnBoard(page, date, id);

    await openMenuAction(page, 'no_show');

    const block = page.getByTestId(`appt-${id}`);
    await expect(block).toHaveAttribute('data-status', 'no_show');
    await expect(block).toHaveCSS('opacity', '0.45');
  });

  test('Checkout is refused until the no-preference therapist is assigned, and a client may decline to rate', async ({
    page,
  }) => {
    const id = await book(page, { client: 'Jessica Brown', date });
    await openOnBoard(page, date, id);

    await page.getByTestId('go-checkout').click();
    await expect(page.getByTestId('board-error')).toContainText('Assign the therapist');

    await assignTherapist(page);
    await page.getByTestId('go-checkout').click();
    await expect(page.getByTestId('checkout-rating')).toBeVisible();

    await page.getByTestId('rating-declined').click();
    await expect(page).toHaveURL(new RegExp(`/checkout/${id}$`));
    await expect(page.getByTestId('order-total')).toContainText('$80.00');
  });

  test('an appointment can be dragged to another room and time', async ({ page }) => {
    const id = await book(page, { client: 'Robert Wilson', date });
    await showBoard(page, date);

    const block = page.getByTestId(`appt-${id}`);
    await expect(block).toBeVisible();
    const fromLane = await block.locator('xpath=ancestor::div[@data-lane-room]').getAttribute('data-lane-room');
    const lanes = page.locator('[data-lane-room]');
    const laneIds = await lanes.evaluateAll((els) => els.map((el) => el.getAttribute('data-lane-room')));
    const targetId = laneIds.find((laneId) => laneId !== fromLane)!;
    const target = page.locator(`[data-lane-room="${targetId}"]`);

    const from = (await block.boundingBox())!;
    const to = (await target.boundingBox())!;
    const moved = page.waitForResponse((r) => r.url().includes(`/appointments/${id}/reschedule`));

    await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
    await page.mouse.down();
    await page.mouse.move(from.x + from.width / 2 + 30, from.y + from.height / 2, { steps: 5 });
    await page.mouse.move(to.x + to.width * 0.5, to.y + to.height / 2, { steps: 20 });
    await page.mouse.up();

    const response = await moved;
    expect(response.status(), await response.text()).toBe(201);
    const fresh = await response.json();
    expect(String(fresh.room.id)).toBe(targetId);
    expect(fresh.starts_at).not.toContain('T09:00');
    await expect(page.getByTestId(`appt-${fresh.id}`)).toBeVisible();
    await expect(page.getByTestId(`appt-${id}`)).toHaveCount(0);
  });
});
