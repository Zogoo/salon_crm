# Platform Feedback — Coverage Report

**Compared against:** `docs/platform-feedback-list.md`
**Code reviewed:** commit `a470f12` ("Feedback: adjustment and bug fix") plus the uncommitted working tree
**Checks run:** 322 backend examples, 34 frontend tests, production build, rubocop, brakeman — all green.
**Not yet done:** a browser walkthrough of these flows. Verdicts below come from reading the code and the passing test suites.

> **Update 2026-09-15 — gaps closed.** The business decided: deposits are recorded in the salon; Managers may discount up to a per-location limit; no-shows stay on the calendar, faded; therapists may read internal notes. Every partial item below is now built, and the flows are covered by an automated browser suite (`e2e/`) that runs against the production image and gates every deploy. The status table reflects the current state. The detailed sections underneath are the original review.

## Summary

| # | Request | Status |
|---|---|---|
| 1.1 | Cancelled appointments removed from calendar | ✅ Covered |
| 1.2 | Drag-and-drop to another time or room | ✅ Covered — mouse and touch (pointer events) |
| 1.3 | Edit service, add-ons and discount from calendar | ✅ Covered — Managers up to the location limit |
| 2.1 | Couple / four-hands availability with specific therapists | ✅ Covered — both therapists can be named |
| 2.2 | "No preference" stays unassigned; assign later; internal notes | ✅ Covered — now also enforced on the server |
| 3.1 | Ask for a 1–10 rating before checkout | ✅ Covered — with "Client declined to rate" |
| 3.2 | Deposit and discount fields at checkout | ✅ Covered — deposit held until checkout |
| 3.3 | One-click Checkout plus a ⋮ menu | ✅ Covered — one server action; Cancel after check-in |
| 4.1 | Rating column in visit history | ✅ Covered |
| 4.2 | Gift cards purchased, on the client profile | ✅ Covered |
| 5.1 | Enter and edit earnings directly | ✅ Covered |
| 6.1 | Edit service name and session length | ✅ Covered |
| 7.1 | Enter a gift card code, or auto-generate one | ✅ Covered — clear "already in use" message |

**13 covered.** (Originally 10 covered, 3 partial.)

---

## 1. Calendar / Schedule

### 1.1 Cancelled appointments not removed from calendar — ✅ Covered
The board now queries `Appointment.active` (`appointments_controller.rb:25`), which contains only `pending_approval`, `scheduled`, `checked_in`, `in_progress` and `completed`. Cancelled, late-cancelled and no-show appointments no longer appear on the calendar, so they cannot cover a new booking.

- **Worth confirming with the business:** no-shows are hidden too. The request only mentioned cancellations, and the desk may still want to see who didn't turn up that day.

### 1.2 Drag-and-drop rescheduling — ✅ Covered (mouse only)
Appointments can be dragged to a new time and room (`day-board.ts:368–390`). The drop point is snapped to the 15-minute grid and kept inside opening hours. The move goes through reschedule, so the old slot is released and the new one is conflict-checked. A confirmed therapist stays assigned; a no-preference booking stays unassigned.

- **Gap:** this uses native HTML5 drag, which doesn't work with touch. It will not work on the front-desk pad (tablet). The reschedule date/time/room fields in the panel still work there.

### 1.3 Edit appointment directly from calendar — 🟡 Partial
The appointment panel on the calendar now offers:
- **Change the service** — `replaceService` keeps the time, room, confirmed therapist and existing add-ons.
- **Add or remove add-ons** — `addExtra` / `removeExtra`. The extra time is re-checked for conflicts.
- **Apply a discount** — `applyDiscount` opens the order and records a discount with a reason.

- **Gap:** the discount endpoint is Owner-only (`orders_controller.rb:103`, `require_owner!`). A Manager at the desk will get a permission error. The business needs to decide whether Managers may give discounts, and if so, up to what limit.

---

## 2. Booking Flow

### 2.1 Couple / four-hands: no availability with specific therapists — 🟡 Partial
The backend is fixed. Availability search no longer narrows a two-therapist service down to the one named therapist's shifts. It now requires that therapist to be among the free ones and fills the second seat automatically (`availability_search.rb`, `book_appointment.rb`).

- **Gap:** booking still has a **single** therapist dropdown (`booking.html:210`). A client can ask for one named therapist, but not for *both* therapists of a couple's or four-hands session.
- **Workaround today:** book with one named therapist (or No preference), then use **Assign therapist** in the calendar (2.2) to choose both.

### 2.2 "No preference" auto-assigns a therapist — ✅ Covered
- New column `appointments.staff_assignment_confirmed` (existing appointments default to `true`).
- A no-preference booking now keeps a *provisional* therapist reservation, so double-booking protection still holds. The desk sees it as unassigned until someone confirms a therapist.
- **Assign therapist** in the calendar panel asks for exactly the number of therapists the service needs. It checks qualification, shift, breaks and conflicts, and writes an audit row (`assign_appointment_staff.rb`).
- **Internal notes** can be saved from the panel (`saveInternalNote` → `PATCH /appointments/:id`).
- Checkout is blocked until a therapist is assigned, so earnings always go to a real therapist.

---

## 3. Checkout

### 3.1 Request client feedback before checkout — ✅ Covered (no way to skip)
Clicking **Checkout** opens a 1–10 score prompt with an optional comment. The rating is saved first, then the appointment moves on to checkout (`submitRatingAndCheckout`). The prompt sits inside the appointment panel, which appears as a bottom sheet on a tablet and a side panel on desktop.

- **Gap:** the score is required. The only other button is Cancel, which closes the prompt. A client who declines to rate therefore blocks checkout. Add a **"Client declined"** option that continues without saving a rating.

### 3.2 Add deposit and discount fields — 🟡 Partial
- **Discount:** ✅ at checkout, with a reason, audit-logged (`checkout.html:147–160`, `Sales::ApplyDiscount`). Owner-only — see 1.3.
- **Deposit:** ❌ not implemented. The only trace is a `deposit_percent` setting on locations, which belongs to the Release 2 online-booking deposit (Stripe).
- **Needs a decision:** is this a deposit **taken in the salon ahead of the visit** (for example by phone), recorded against the appointment and deducted at checkout? If so, it's Release 1 work. It also needs its own reporting treatment: until the service is completed, a deposit is money held for the client, not revenue.

### 3.3 Simplify the checkout flow — ✅ Covered (with gaps)
- **Checkout** shows directly in the calendar panel for scheduled, checked-in, in-progress and completed appointments.
- Checkout moves the appointment through checked in → in progress → completed automatically, then opens the checkout screen (`completeAndCheckout`). The desk no longer clicks through each step.
- **⋮ menu:** Cancel, No-show, Rebook, Reschedule, Add notes, Set as repeating. Repeats are weekly, 1–4 weeks apart, up to 12, and if any one date is unavailable none are created.

- **Gap:** once an appointment is checked in, the menu no longer offers **Cancel** (`day-board.ts:486`), even though the backend allows it. A client who checks in and then leaves can only be marked as a no-show.
- **Gap:** the automatic steps are three separate requests. If one fails partway (for example a network drop), the appointment is left checked in or in progress with an error shown. The desk can click Checkout again to finish, but a single server-side "complete for checkout" action would be safer.

---

## 4. Clients

### 4.1 Ratings column in visit history — ✅ Covered
Visit history has a Rating column showing `score / 10` for each visit that has one (`clients.html:225–241`). The ratings API now returns `appointment_id` so each score sits on the right visit.

### 4.2 Gift card purchase info — ✅ Covered
The client profile lists gift cards the client **bought**, with code, value, balance and sale date (`clients.html:262+`). The sale date is in salon local time.

- **Note:** cards the client *received* as a gift are not listed. The request said "purchased", so this matches it.

---

## 5. Staff Earnings

### 5.1 Simplify earnings entry — ✅ Covered
- Manual entries are an **amount** now, not a session quantity (`earnings.html:115–133`).
- Manual lines can be edited later from a column in the line list (`PATCH /earning_lines/:id`, `Earnings::UpdateManualLine`). Old and new values are recorded in the audit log.
- Edits are refused once the pay period is locked (BR-37), and Owner-only.

- **By design:** lines generated from completed appointments and tips cannot be hand-edited, because they are recalculated from the appointment. Fix those through an adjustment, or by correcting the appointment.

---

## 6. Service Menu

### 6.1 Edit existing services — ✅ Covered
- Service name, and the other service details, can be edited (`catalogue-admin.html:91–122`).
- Each session length can be edited: duration, therapists needed, seats, active (`editVariant`, `updateVariant`).
- Durations still have to be 30/45/60/75/90/120 so therapist pay can be calculated (BR-33).
- Appointments already booked keep the service and price they were booked with (BR-11).

---

## 7. Gift Cards

### 7.1 Manual code or auto-generated code — ✅ Covered
An optional **Code** field is on the sell form (`giftcards.html:16–20`). Codes are stored uppercase with spaces trimmed. Leave the field blank and a `GC-XXXXXXXXXX` code is generated (`GiftCards::IssueCard`, `GiftCard.generate_code`).

- **Gap:** entering a code that already exists is refused, but the controller doesn't handle that case. The desk sees a generic error instead of "This code is already in use."

---

## Additional Owner features found in the same change set

These weren't in the feedback list, but they expose existing API capability to the Owner:

| Feature | State |
|---|---|
| **Audit log** screen and `GET /audit_logs` — Owner-only, filter by action, record type, person and date; paginated | ✅ Working, 2 timezone bugs below |
| **Profile** with two-step login (authenticator app) enrolment | ✅ Wired to `/me/otp` |
| **Password reset** page (`/reset-password/:token`) | ✅ Wired |
| **Public rating page** (`/rate/:token`) for the text-message link | ✅ Wired to `/public/ratings/:token` |
| **Staff requests** screen (request, approve, reject, withdraw) | ✅ Wired |
| **My notes** now in the menu | ✅ Routed |

**Audit log timezone bugs:**
1. **Times are in UTC.** `audit_logs_controller.rb` sends `occurred_at.iso8601`, which ends in `Z`. Every other endpoint sends salon local time, so entries on this screen appear 5–6 hours off. The existing timezone spec doesn't cover this endpoint.
2. **Date filter uses UTC days.** `AuditLogsQuery` builds day boundaries with `Time.zone.parse(...)`. An action after about 7pm Central appears under the next day's date.

---

## Remaining work — status

| # | Item | Status |
|---|---|---|
| R1 | Deposit taken in the salon | ✅ Done. Recorded against the appointment, held as the client's money, taken off the bill at checkout. Refunded on a cancellation in time; on a late cancel or no-show the fee is taken from it first. Shown in the revenue report as held, not as revenue. |
| R2 | Manager discounts | ✅ Done. Up to the location's `manager_discount_limit_percent` (default 20%, set by the Owner on Location settings). The Owner has no limit. Every discount records who gave it and why. |
| R3 | Name both therapists for couple / four-hands | ✅ Done in the booking screen (second therapist select). Not yet covered by an automated test. |
| R4 | "Client declined to rate" | ✅ Done. E2E-tested. |
| R5 | Cancel for checked-in appointments | ✅ Done. |
| R6 | Single server-side "complete for checkout" | ✅ Done (`POST /appointments/:id/complete_for_checkout`). E2E-tested. |
| R7 | Touch-friendly moving | ✅ Done with pointer events. The mouse path is E2E-tested; still try it once on the front-desk tablet. |
| R8 | Duplicate gift card code message | ✅ Done. E2E-tested. |
| R9 | Audit log in salon time and business day | ✅ Done. The underscore filter bug found by the E2E suite is fixed too. |
| R10 | No-shows on the calendar | ✅ Done. Shown faded, with no actions, and they never block the slot. |
| R11 | Browser walkthrough | ✅ Replaced by the automated E2E suite that gates deploys. A short manual check on the tablet is still recommended for touch drag (R7). |
