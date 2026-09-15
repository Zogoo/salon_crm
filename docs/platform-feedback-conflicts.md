# Platform Feedback — Conflict Analysis

**Question:** do any of the implemented feedback requests (`docs/platform-feedback-list.md`) conflict with each other, or break existing rules in `docs/01-business-analysis.md`?

**Status.** None of this code has been deployed to production, and no real appointment, payment or pay run has used it. Everything below is a **pre-release defect**: severity describes what *would* happen once released, not damage that has occurred. For the same reason, none of the fixes need data repair or backfills — correcting the code is enough, and the review environment can simply be re-seeded.

## Resolution (2026-09-15)

All twelve are now addressed in code, each with a regression spec (`spec/services/prerelease_conflicts_spec.rb`, `spec/requests/api/v1/prerelease_api_spec.rb`), and the main flows are covered by the end-to-end suite that now gates every deploy (`e2e/`, `bin/e2e`).

| # | Resolution |
|---|---|
| C1 | **Fixed.** While no money has been taken, an order's lines are rebuilt from its appointment on every change (`Sales::SyncOrder`). Once a payment, gift card or membership credit is on it, appointment edits are refused with `order_has_payments`. |
| C2 | **Fixed.** Reschedule, change of service and drag-and-drop carry the order, its discount and any deposit to the new appointment. Cancelling voids an unpaid early order. |
| C3 | **Fixed.** Manual discounts and membership credits are capped at what is left of the order and at what is still outstanding. Discounts are refused on closed orders, and a reason is required. |
| C4 | **Fixed.** Manual discounts are netted out of service revenue. The report shows gross services, discounts, deposits taken and deposits held as separate lines. |
| C5 | **Fixed.** A moved or repeated request stays `pending_approval` and keeps its original 45-minute clock. The old request is withdrawn. The auto-approval job closes stale requests and handles each record separately, so one bad record can't stop the others. The Approvals list shows only appointments still waiting. |
| C6 | **Fixed.** The server refuses completion and settlement until a therapist is confirmed. A provisional therapist no longer sees the appointment or its care notes. Checkout is one server action (`complete_for_checkout`). |
| C7 | **Fixed.** Message details are rebuilt at send time. A provisional therapist is never named, and reminders for visits no longer going ahead are skipped. |
| C8 | **Fixed.** No rating text is queued when the client already rated at the desk. |
| C9 | **Mitigated.** Repeats are still all-or-nothing, deliberately. The refusal now lists every failing date and why (typically "not on shift" past the published roster), and repeats of a pending request stay pending. |
| C10 | **Fixed.** Length, therapist count, seats and room type can't change while upcoming bookings or an active membership use that length (`variant_in_use`). Name, price and active status stay editable. |
| C11 | **Fixed.** Services have a stable `code`, and seeds match on it. |
| C12 | **Fixed.** Manual earnings default to an amount only, with no session length, so they no longer add phantom sessions. |

**Found by the new end-to-end suite and fixed:**
- The calendar's "Discount applied" and "repeats booked" confirmations never appeared, because the app is zoneless and the values weren't signals.
- The audit log's action filter matched nothing for any action containing `_` (`gift_card`, `care_notes`…), because SQLite's `LIKE` needs an explicit `ESCAPE`.

The analysis below is kept as written, for the record.

---

**Method.** Every path where a new feature touches another was traced in the code. The six highest-impact ones were also **run** in a throwaway spec (since deleted), so the numbers below are real output, not estimates. Each item is marked:

- **Proven** — reproduced by running the code.
- **Confirmed in code** — the path is clear in the code, but it is dormant (for example, it only matters once notifications are sent) or wasn't worth a probe.

## Summary

Severity means impact if released as-is.

| # | Conflict | Features involved | Rules affected | Severity | Evidence |
|---|---|---|---|---|---|
| C1 | Order falls out of step with the appointment once a discount is applied early | 1.3 discount × 1.3 add-ons × 3.3 checkout | BR-22, BR-33 | **High — money** | Proven |
| C2 | Changing the service, dragging or rescheduling loses the discount and leaves an orphaned order | 1.3 discount × 1.3 replace service × 1.2 drag × 3.3 reschedule | BR-22 | **High — money** | Proven |
| C3 | Order totals can go negative | 1.3 / 3.2 discount × membership credit | BR-22, BR-39 | **High — money** | Proven |
| C4 | Daily revenue overstates service revenue when a discount is given | 1.3 / 3.2 discount × reports | BR-48 | **High — reporting** | Proven |
| C5 | Moving a pending-approval appointment approves it silently, and the leftover request stops auto-approval for everyone else | 1.2 drag × 1.3 replace × 3.3 reschedule / repeat | BR-15, BR-15a | **High — rules** | Proven |
| C6 | An unassigned therapist gets paid, rated and credited if the appointment is completed before assignment | 2.2 × 3.3 | BR-32, BR-34, BR-44, BR-45 | **High — pay** | Proven |
| C7 | Confirmations and reminders name the provisional therapist | 2.2 × notifications | FRS §22 | Medium — dormant | Confirmed in code |
| C8 | The client is asked to rate twice | 3.1 × rating text link | FRS §11.2 | Low — dormant | Confirmed in code |
| C9 | Repeating appointments fail whenever a week is past the published roster | 3.3 repeat × roster | BR-08 | Medium | Confirmed in code |
| C10 | Editing a session length or therapist count affects existing bookings and the membership | 6.1 × 2.2, 1.3, membership | BR-39, BR-09 | Medium | Confirmed in code |
| C11 | Renaming a seeded service and re-running seeds creates a duplicate | 6.1 × seeds | — | Low | Confirmed in code |
| C12 | Each manual earnings amount adds a phantom session to the quantity table | 5.1 × earnings report | FRS §4, §8 | Low–medium | Confirmed in code |

**Checked and not a conflict:** 1.1 (hiding cancellations), 2.1 (couple availability), room choice on drag-and-drop, earnings generated twice, 4.1 / 4.2, 7.1, and the audit log. Details at the end.

---

## C1 — Order falls out of step with the appointment · High · Proven

**What happens.** **Apply discount** in the calendar (1.3) opens the checkout order *before* the appointment is completed. `Sales::OpenOrder` copies the appointment's items into the order **once**; afterwards it just returns the existing order without updating it. If an add-on is then added from the same panel (1.3), the appointment changes but the order doesn't.

**Proof (probe):**
```
order subtotal before=8000  after add-on=8000   appointment total now=11500
earnings after completion: ["90min=6750"]
```

**Impact if released.** The client would be charged **$80 instead of $115**. The therapist is still paid the 90-minute rate, because earnings are calculated from the appointment, not the order. The same path means **removing** an add-on after a discount leaves it on the bill. BR-22 settles against a stale total.

**Fix direction.** Don't open an order before checkout. Either store a calendar discount as a pending discount on the appointment and apply it when the order opens, or block item and service changes once an order exists.

---

## C2 — Discount lost, orphaned order · High · Proven

**What happens.** Changing the service (1.3), dragging (1.2) and rescheduling (3.3) all go through `RescheduleAppointment`. That cancels the original appointment and books a new one. Any order already opened by the calendar discount stays attached to the **cancelled** appointment.

**Proof (probe):**
```
old appt=cancelled  old order status=open  discount=1000   new appt order? false
```

**Impact if released.** The discount the desk applied would disappear from the real checkout. An open order with money on it is left on a cancelled appointment, and no screen or report shows it: the outstanding-fees report only lists `kind: "fee"` orders.

**Fix direction.** Same as C1. Also, when an appointment is moved, move or void any order that belongs to it.

---

## C3 — Negative order totals · High · Proven

**What happens.** `Sales::ApplyDiscount` only checks that the amount is positive. It doesn't check the amount against what's left on the order, or whether the order is already paid. `Memberships::RedeemCredit` caps the credit at the order **subtotal** and ignores any discount already applied.

**Proof (probe):**
```
discount larger than order:  subtotal=8000 discount=13000 total=-5000 outstanding=-5000
discount $20 + membership:   subtotal=8000 discount=10000 total=-2000
```

**Impact if released.** Totals would go negative. The order records a client overpayment that BR-22 says must be rejected. The order total is `subtotal − discount + tip`, so a large discount can also swallow the tip, even though the therapist's tip allocation still records the full amount (BR-24a).

**Fix direction.** Cap every discount, manual or membership, at `subtotal − discounts already applied`. Refuse discounts on paid orders; use a refund instead (BR-23).

---

## C4 — Revenue report overstates service revenue · High · Proven

**What happens.** `Reporting::DailyRevenue` adds up the order's line items for service revenue and never subtracts discounts. This bug existed before the feedback work, but discounts were rare. Requests 1.3 and 3.2 put discounts in front of the desk every day.

**Proof (probe):**
```
subtotal=8000 discount=2000 collected=6000 service_revenue=8000
```

**Impact if released.** The report would show $80 of service revenue for a $60 sale. BR-48's three categories (revenue, liabilities, fees) no longer add up to what was collected.

**Fix direction.** Net manual discounts out of service revenue, or show them as their own line on the report.

---

## C5 — Approval bypassed, then auto-approval halted · High · Proven

**What happens.**
1. A specific-therapist booking is `pending_approval` (BR-15).
2. Dragging it (1.2), changing its service (1.3), rescheduling or repeating it (3.3) calls `BookAppointment` with a list of therapists but without the specific-therapist request. So the new appointment is created as **`scheduled`**: approved without anyone approving it.
3. The old `ApprovalRequest` stays **pending**, attached to a cancelled appointment.
4. When the auto-approval job reaches that request, it tries to move a cancelled appointment to scheduled and raises an error.

**Proof (probe):**
```
after move: old=cancelled new=scheduled approvals still pending=1
job raised Scheduling::TransitionStatus::Invalid: cannot move from cancelled to scheduled
```

**Impact if released.**
- **BR-15 bypassed:** moving a request would confirm it.
- **BR-15a would stop working:** the job walks requests oldest first and nothing catches the error. The stale request would fail on every run, and every newer request behind it would **never be auto-approved**, however long it waited.
- The **Approvals** screen keeps listing the dead request, with its waiting timer still running, because the list doesn't filter out cancelled appointments.

**Fix direction.** Keep the pending status (and the specific-therapist request) when moving a pending-approval appointment, and close or transfer the old request. The job should skip requests whose appointment is no longer pending, and catch errors per request so one bad record can't block the rest.

---

## C6 — Unassigned therapist gets paid · High · Proven

**What happens.** A no-preference booking (2.2) holds a *provisional* therapist while it waits for assignment. The only thing stopping completion before assignment is the frontend **Checkout** button. `TransitionStatus`, which the transition API and the therapist's own buttons use, doesn't check `staff_assignment_confirmed`.

**Proof (probe):**
```
confirmed=false provisional=["T0"]
earning lines=1 for staff=["T0"]
```

**Impact if released.** When completion happens before assignment:
- The provisional therapist is paid for work someone else may have done (BR-32, BR-34).
- The rating link and the rating itself are tied to the wrong therapist (BR-45).
- That therapist can already read and write care notes on the appointment (BR-44 access is "the therapist on that appointment").

**Fix direction.** Enforce assignment on the server. Refuse `completed` and opening an order while `staff_assignment_confirmed` is false. Decide whether a provisional therapist should see the appointment and its care notes at all.

---

## C7 — Messages name the provisional therapist · Medium · Confirmed in code · dormant

`Notifications::Confirm` builds the confirmation and both reminders' text at **booking time**, including `staff_profiles.map(&:display_name)`. For a no-preference booking that is the provisional therapist. The reminders are stored with that name, so a later reassignment doesn't update them.

**Impact once notifications are sent (#2):** clients are told the wrong therapist, twice.
**Fix direction:** build the message text when it's sent, and leave the therapist out while the assignment is unconfirmed.

---

## C8 — Rating asked twice · Low · Confirmed in code · dormant

The desk now collects the rating before checkout (3.1). Completion still always queues the `rating_request` text message (`TransitionStatus#request_rating!`). The client then receives a link that answers "already rated".

**Fix direction:** skip `rating_request` when the appointment already has a rating.

---

## C9 — Repeats vs the published roster · Medium · Confirmed in code

`RepeatAppointment` books each week through `BookAppointment`, which requires a **published shift** (BR-08), and the series is all-or-nothing. Repeats can run up to 12 weeks ahead, but rosters are usually published only a week or two ahead. Any repeat that reaches past the published roster fails **entirely**.

Also:
- A repeat of a pending-approval appointment is booked `scheduled`, skipping approval (same cause as C5).
- Once notifications are live, each repeat sends its own confirmation and two reminders the moment it is created.

**Fix direction:** limit repeats to the published roster, or create them as held or unassigned bookings that are checked when the roster is published. Report which dates failed rather than failing the whole series.

---

## C10 — Editing session lengths affects bookings and the membership · Medium · Confirmed in code

`ServiceVariantsController#update` lets the Owner change `duration_minutes`, `therapist_count` and `required_client_capacity` on any variant (6.1), with no checks.

- **Membership (BR-39):** the $80 membership's included massage points at a specific variant. Change that variant from 60 to 90 minutes and the membership now includes a 90-minute massage.
- **Existing bookings:** price and pay are protected, because appointment items keep their own copies of duration and price (BR-11, BR-33). But assigning therapists (2.2), changing the service (1.3), adding add-ons and rescheduling all read the **current** variant. A couples booking whose variant was edited to one therapist then asks for one therapist while two are held, and rescheduling it may choose a different room.

**Fix direction:** refuse duration, therapist-count and seat changes on a variant that has future active bookings or is a membership's included massage. Ask the Owner to create a new length and retire the old one instead.

---

## C11 — Seeds duplicate a renamed service · Low · Confirmed in code

`db/seeds/catalogue.rb` matches services **by name** (`find_or_create_by!(name:)`), and the seeds are documented as safe to re-run. Rename a seeded service (6.1) and run `db:seed` again, and a second copy of the original service is created with default prices.

Production only seeds a brand-new database, so the risk is limited to a manual re-seed.

**Fix direction:** match seeded services on a fixed code instead of the name.

---

## C12 — Manual amounts add phantom sessions · Low–medium · Confirmed in code

Earnings entry is now an amount (5.1), but the screen still sends a session length and **quantity 1** with every entry (`earnings.ts` → `addEarningLine`). Each correction or off-system payment therefore adds one session to the 30/45/60/75/90/120 quantity table (FRS §4, §8) and to the statement's session count, even when no session happened.

**Fix direction:** save pure amount corrections without a session length (or as an adjustment), so they count towards pay but not towards session quantities.

---

## Checked — no conflict

| Area | Why it is safe |
|---|---|
| **1.1 Hiding cancelled appointments** | Conflict checks already ignored cancelled, late-cancelled and no-show appointments; only what's displayed changed. Fees stay visible on the client profile, as BR-19 intends. |
| **2.1 Couple availability** | A named therapist no longer narrows the search to their shifts alone; they just have to be among the free therapists. The pending-approval hold (BR-15) still applies. |
| **1.2 Room on drag-and-drop** | An explicitly chosen room is still checked for capacity and head-spa suitability (`BookAppointment#resolve_room`, BR-09 / BR-09b) and for conflicts. |
| **Earnings generated twice** | Earnings are now generated at completion *and* at settlement, but `GenerateForAppointment` does nothing if session lines already exist, so nobody is paid twice. |
| **4.1 / 4.2 Client history** | Read-only views. |
| **7.1 Manual gift card codes** | Codes are normalised and must be unique. |
| **Audit log** | Read-only and Owner-only. Its only problems are the two timezone bugs in the coverage report. |

## Open question for the business

**Internal notes (2.2).** The appointment's `appointment_note` is returned to therapists too. If "internal" means front desk only, therapists can currently read these notes.

## Suggested order of work

1. **C1, C2, C3** — one change: open the order only at checkout, cap discounts, and handle orders when an appointment moves.
2. **C5** — without it, one moved request would halt auto-approval for every location.
3. **C6** — server-side assignment check before completion.
4. **C4** — report fix; needed before anyone relies on the revenue report.
5. **C9, C10, C12**, then **C7, C8** before notifications are switched on, then **C11**.
