# Massage Salon CRM — Business Analysis

**Version:** 1.0 · **Date:** 2026-08-14 · **Status:** For review, pre-implementation

---

## 1. Business Context

A single massage salon company operating **2–10 physical locations**. Each location contains a
number of **massage rooms**. Revenue comes from **massage services** delivered by **therapists**
in those rooms, plus **gift card** sales.

The scarce resources of the business are:

1. **Therapist time** — a qualified, scheduled, on-shift therapist.
2. **Room time** — a physical room at that location.

Every appointment consumes exactly one of each, simultaneously. The entire commercial performance
of the business is a function of how well those two resources are matched to demand. This is why
the scheduling engine (doc 03) is the architectural centre of gravity, not the CRM record-keeping.

### 1.1 Confirmed scope decisions

| Decision | Answer |
|---|---|
| Booking channels | Phone (manager), walk-in, customer self-service online, staff self-service |
| Payments | **Recorded, not processed.** No card gateway in v1. |
| Payment methods | Cash, Card, Zelle, Online |
| Scale | Single company, 2–10 locations |
| Stack | Rails API + AngularJS SPA, served from one Rails project |
| Resource model | 1 appointment = 1 room + 1 therapist |
| Staff pay | Hourly rate × **scheduled shift hours** |
| Staff ↔ location | Many-to-many; a therapist may work at any location |
| Shift workflow | Staff submit availability → manager approves; recurring weekly patterns; time-off requests |
| Roles | Owner/Admin, Location Manager, Front Desk, Therapist |
| Customer record | Profile + visit history, health intake + consent, per-visit SOAP notes, preferences, no-show history |
| Gift cards | Stored-balance (partial redemption), fixed denomination, and service-specific variants |
| Pricing | Per service, varying by duration and by location; packages/memberships in scope |
| Notifications | Email confirmations + reminders; cancellation window + no-show tracking |
| Deployment | Single cloud server + Postgres |

---

## 2. Actors

| Actor | Description | Primary goals |
|---|---|---|
| **Owner / Admin** | Business owner or head office. Access to all locations. | Company-wide revenue, utilisation, payroll cost, staff performance |
| **Location Manager** | Runs one or more branches. | Fill the schedule, approve shifts, onboard staff, manage rates, close the month |
| **Front Desk / Receptionist** | Answers the phone, greets walk-ins, takes payment. | Book fast, check in/out, take payment, sell gift cards. **Must not see pay rates or health notes.** |
| **Therapist (Staff)** | Delivers the massage. | Submit availability, see own schedule, see own hours/earnings, write SOAP notes |
| **Customer** | Buys and receives services. | Book online, see history, buy/redeem gift cards |
| **System (scheduled jobs)** | Non-human actor. | Send reminders, generate recurring shifts, close pay periods, refresh reports |

### 2.1 Separation-of-duties rules

These are hard requirements, not preferences:

- **Front Desk must never see** `staff_rates`, pay statements, salary reports, health intake data,
  or SOAP notes.
- **Therapists see only their own** schedule, availability, hours, pay statements, and only the
  SOAP notes / intake of customers they are scheduled with.
- **Location Managers see only their assigned locations'** staff, appointments, and reports —
  including rates of staff who work at their locations.
- **Owner/Admin sees everything** and is the only role that can change a rate retroactively, void a
  payment, or adjust a gift card balance. Every such action is audit-logged.

---

## 3. Core Business Processes

### 3.1 Staff onboarding

1. Manager creates a **Staff** record: personal details, employment type, hire date.
2. Manager assigns **locations** the staff may work at (one or many).
3. Manager assigns **service qualifications** — which massage services this therapist is certified
   to perform. *A therapist can never be booked for a service they are not qualified for.*
4. Manager sets the **hourly rate** with an `effective_from` date.
5. System creates a user account and sends an invitation email.
6. Staff status becomes `active` → they now appear in availability search.

**Rule BR-01:** A staff member with no service qualifications or no location assignment cannot be
scheduled. The system must warn the manager at onboarding completion.

### 3.2 Staff offboarding

1. Manager sets a **termination date**.
2. System checks for **future appointments** assigned to that staff after the termination date and
   blocks offboarding until they are reassigned or cancelled. This is the single most common source
   of operational chaos in salon systems — it must be enforced, not warned.
3. System cancels/expires **approved future shifts** after the termination date.
4. Staff status → `terminated`. Account login disabled.
5. Historical data (appointments, SOAP notes, timesheets, pay statements) is **retained
   immutably** — never deleted, never anonymised, because it backs past payroll and customer care.

**Rule BR-02:** Offboarding is soft. No hard deletes of staff records, ever.

### 3.3 Availability submission and shift approval

```
Staff                       Manager                     System
  |                            |                           |
  |-- submit availability ---->|                           |
  |   (date range, times,      |                           |
  |    preferred locations)    |                           |
  |                            |-- review -----------------|
  |                            |-- approve → create Shift ->|
  |                            |   (staff, location,       |
  |                            |    start, end)            |
  |                            |-- publish schedule ------>|
  |<-- notified ---------------|                           |
```

Two distinct concepts, often conflated — keep them separate:

- **Availability** = "I *can* work these hours." Staff-owned. A request.
- **Shift** = "You *are* working, at this location, these hours." Manager-owned. Authoritative.
  **Only Shifts drive scheduling and payroll.**

Supported inputs:

- **One-off availability** for specific dates.
- **Recurring weekly patterns** ("every Mon & Wed 09:00–17:00") with an effective date range, from
  which the system materialises concrete availability/shift records forward (see BR-05).
- **Time-off requests** (vacation, sick), which override and block both.

**Rule BR-03:** A Shift may only be created for a staff member at a location they are assigned to.
**Rule BR-04:** Overlapping approved Shifts for the same staff member are forbidden, *across all
locations*. Since staff can work anywhere, this is a company-wide constraint.
**Rule BR-05:** Recurring patterns are materialised into concrete shift records by a nightly job on
a rolling horizon (default 8 weeks). Concrete records can be individually edited without changing
the pattern. Editing the pattern does not retroactively change already-published shifts.
**Rule BR-06:** An approved time-off request blocks shift creation and flags any already-booked
appointments in that window for manager reassignment.

### 3.4 Booking an appointment

The same core transaction regardless of channel (phone, walk-in, online).

```
1. Identify customer         → search by phone/email, or create new
2. Choose service + duration → resolves to a ServiceVariant
3. Choose location           → resolves the price and the room pool
4. Search availability       → engine returns bookable slots (doc 03)
   ├─ optionally filtered by preferred therapist
   └─ filtered by therapist qualification for the service
5. Select slot               → system holds room + therapist
6. Confirm                   → Appointment created, price snapshotted
7. Notify                    → confirmation email; reminder scheduled
```

**Rule BR-07:** An appointment must reference a therapist who (a) is qualified for the service,
(b) has a published shift covering the whole appointment at that location, and (c) has no
overlapping appointment anywhere.
**Rule BR-08:** An appointment must reference an active room at that location with no overlapping
appointment.
**Rule BR-09:** The **price is snapshotted** onto the appointment at booking time. Later price-list
changes never alter a booked or completed appointment.
**Rule BR-10:** Online self-service bookings may only be made into the future beyond a configurable
lead time (default 2 hours) and within a booking horizon (default 60 days).

### 3.5 Appointment lifecycle

```
                    ┌─────────────┐
                    │  scheduled  │ ← created (any channel)
                    └──────┬──────┘
             ┌─────────────┼──────────────┬─────────────────┐
             ▼             ▼              ▼                 ▼
     ┌─────────────┐ ┌───────────┐ ┌──────────────┐ ┌──────────────┐
     │ checked_in  │ │ cancelled │ │ late_cancel  │ │   no_show    │
     └──────┬──────┘ └───────────┘ └──────────────┘ └──────────────┘
            ▼          (outside      (inside          (never arrived)
     ┌─────────────┐    window)       window)
     │ in_progress │
     └──────┬──────┘
            ▼
     ┌─────────────┐        ┌──────────────┐
     │  completed  │───────▶│     paid     │ (order settled)
     └─────────────┘        └──────────────┘
```

**Rule BR-11:** Only `completed` appointments generate revenue. `no_show` and `late_cancelled`
generate revenue **only** if a fee policy is configured (see open question OQ-04).
**Rule BR-12:** `cancelled` vs `late_cancelled` is determined by the location's cancellation window
(default 24h) measured from `appointment.starts_at`.
**Rule BR-13:** Every `no_show` and `late_cancelled` increments a counter on the customer record.
Front desk sees this counter when booking that customer again.
**Rule BR-14:** Cancelling an appointment immediately frees the room and therapist for rebooking.
Status transitions are the only mechanism for releasing a resource.

### 3.6 Check-in, service, checkout

1. Customer arrives → Front Desk sets `checked_in`.
2. **First visit only:** customer completes the **health intake form** and signs the consent
   waiver. Blocks progression until captured.
3. Therapist starts → `in_progress`. Room occupancy is now physically real.
4. Therapist finishes → `completed`, then writes the **SOAP note** for the visit.
5. Front Desk opens the **Order**: service line item at the snapshotted price, minus any discount,
   plus tip if given.
6. Front Desk records **payment(s)**: cash, card, Zelle, online, and/or gift card redemption.
   An order may be settled by **multiple payments of mixed methods** (split payment).
7. Order status → `paid`.

**Rule BR-15:** An order is `paid` only when `sum(payments) + sum(gift_card_redemptions) >= total`.
Overpayment is rejected; the difference must be entered as a tip or a change amount.
**Rule BR-16:** SOAP notes are **append-only**. Corrections are new entries referencing the
original, never edits. This protects the clinical record.
**Rule BR-17:** A payment record, once created, cannot be edited. It can only be **voided** by a
Manager or Owner (audit-logged) and re-entered.

### 3.7 Gift card lifecycle

Three product types, all issued from the same `gift_cards` table with a discriminator:

| Type | Behaviour |
|---|---|
| **Stored value** | Holds a dollar balance. Each redemption deducts. Partial use allowed. |
| **Fixed denomination** | Issued at a set face value (e.g. $50/$100/$200). Modelled as stored value with a constrained initial amount. |
| **Service-specific** | Entitles the bearer to one specific service variant (e.g. one 60-min Swedish). Redeemed in full against that service. |

```
create → sold (buyer recorded, payment taken) → active
   → partially redeemed (balance > 0)  ─┐
   → fully redeemed (balance = 0)      ─┤→ closed
   → expired (past expires_at)         ─┘
```

**Rule BR-18:** Gift card balance is **never a mutable column used as the source of truth**. It is
derived from an append-only `gift_card_transactions` ledger (issue, redeem, refund, adjust). The
`current_balance` column is a maintained cache, reconciled nightly.
**Rule BR-19:** Selling a gift card is **not revenue** — it is a **liability** (deferred revenue).
Revenue is recognised when the card is redeemed against a service. Reporting must show
outstanding gift card liability separately. This is the single most common accounting error in
salon systems.
**Rule BR-20:** Both the **purchaser** and the **redeemer** are recorded per transaction; they are
frequently different people (it is a gift).
**Rule BR-21:** A service-specific card may only be redeemed against its designated service
variant, at any location, unless location-restricted at issue.
**Rule BR-22:** Redeeming more than the remaining balance is rejected. The shortfall must be paid
by another method on the same order.

### 3.8 Payroll / staff hour summary

Monthly (or configurable pay period) cycle:

1. System aggregates each staff member's **published shift hours** in the period.
2. Manager reviews the timesheet and may apply **adjustments** (late arrival, overtime, correction),
   each with a reason and an audit entry.
3. System applies the **hourly rate that was in effect on each shift's date** — not the current rate.
4. Generates a **Pay Statement**: total hours, rate breakdown, gross amount.
5. Manager **approves and locks** the period. Locked periods are immutable; corrections flow into
   the next period as adjustments.

**Rule BR-23:** Pay is computed from **scheduled (published) shift hours**, not appointment hours,
and not clock-in data. Idle time is paid.
**Rule BR-24:** Rates are **effective-dated**. Historical pay statements must never change when a
rate is updated going forward. A retroactive rate change requires an explicit Owner action that
regenerates unlocked periods only.
**Rule BR-25:** Once a pay period is locked, its shifts become read-only.

### 3.9 Service catalogue management

Manager maintains:

- **Service** — the offering (Swedish Massage, Deep Tissue, Hot Stone…), with a category.
- **Service Variant** — a service at a given **duration** with a **base price** (60-min Swedish,
  90-min Swedish). This is the bookable unit.
- **Location price override** — an optional per-location price for a variant.
- **Buffer time** — turnover minutes appended to the variant for room cleanup.
- **Qualification requirement** — which therapists may perform it.

**Rule BR-26:** Prices are **never edited in place**. A price change creates a new effective-dated
price row. Old appointments keep their snapshot; reports over past periods stay correct.
**Rule BR-27:** A service variant cannot be deleted if any appointment references it — only
deactivated (`active = false`), which hides it from booking but preserves history.

---

## 4. End-to-End Scenario Walkthroughs

### 4.1 Phone booking (the dominant path today)

> Customer calls the Downtown branch. Wants a 90-minute deep tissue on Saturday afternoon, prefers
> Anna.

1. Front Desk searches by phone number → finds existing customer, sees 4 prior visits, preferred
   pressure "firm", and a `no_show_count` of 0.
2. Selects **Deep Tissue / 90 min**, location **Downtown**, date **Saturday**.
3. Filters by therapist **Anna**. Engine returns Anna's free slots where a Downtown room is also
   free: 13:00, 15:30.
4. Customer takes 15:30. Front Desk confirms.
5. System writes the appointment, snapshots the Downtown 90-min deep tissue price, sends a
   confirmation email, and schedules a reminder for Friday 15:30.

**Failure case to design for:** two receptionists at different branches book Anna for the same
15:30 slot at the same instant. See doc 03 §4 — this is prevented at the database level, not in
application code.

### 4.2 Online self-service booking

1. Customer opens the booking page, picks service, duration, location, date.
2. Engine returns **anonymised slots** — the customer sees times, and optionally therapist first
   names, but never room identity or staff internals.
3. Customer picks a slot. System places a **short-lived hold** (default 10 minutes) to prevent the
   slot vanishing during checkout.
4. Customer confirms with name/phone/email. No payment taken (payments are recorded, not processed).
5. Appointment created as `scheduled`. Confirmation email sent.
6. Intake form link included in the confirmation for first-time customers, so it's done before
   arrival.

### 4.3 Walk-in

1. Front Desk searches availability for **now → next 30 minutes** at this location only.
2. Engine returns whichever therapist/room pairs are free right now.
3. Books, checks in, and proceeds in one action.

### 4.4 Month-end close

1. On the 1st, the system snapshots the prior month's published shifts per staff.
2. Managers review timesheets, add adjustments, resolve exceptions.
3. Pay statements generated using effective-dated rates.
4. Owner reviews the company-wide salary cost report against revenue by location.
5. Period locked.

---

## 5. Reporting Requirements

All four confirmed as in-scope. Each drives specific data-model decisions.

| Report | Contents | Model implication |
|---|---|---|
| **Staff hours & salary summary** | Per staff per period: scheduled hours, rate(s) applied, gross pay. Export to XLSX/PDF. | Requires effective-dated rates and locked pay periods |
| **Revenue by location / service / payment type** | Daily, weekly, monthly. Split across cash, card, Zelle, online. **Gift card liability shown separately from revenue.** | Requires order/payment separation and the gift card ledger |
| **Room & staff utilisation** | Booked hours ÷ available hours. Per room, per therapist, per location, per weekday/hour-of-day. | Requires published shift hours AND room open hours as denominators — this is why shifts must be stored as concrete records, not just patterns |
| **Customer retention** | New vs returning, visit frequency, days-since-last-visit, lapsed customers, lifetime value, no-show rate | Requires immutable appointment history and customer-level aggregates |

**Rule BR-28:** Utilisation is meaningless without a defined denominator. Fix it now:
`staff utilisation = booked appointment minutes ÷ published shift minutes`;
`room utilisation = booked appointment minutes ÷ location open minutes for that room`.

---

## 6. Non-Functional Requirements

| Area | Requirement |
|---|---|
| **Availability** | Business-hours critical. Front desk cannot take bookings if the system is down. Target 99.5%, with a printable daily schedule fallback. |
| **Performance** | Availability search < 500 ms for a 7-day window at one location. Front desk booking flow < 3 seconds end to end. |
| **Concurrency** | Zero tolerance for double-booking a room or therapist. Enforced by database constraint. |
| **Data protection** | Health intake and SOAP notes are sensitive health information: encrypted at rest, access-controlled by role, and access-logged. |
| **Auditability** | All changes to rates, payments, gift card balances, appointment status, and pay periods are audit-logged with actor, timestamp, before/after. |
| **Retention** | Financial and clinical records retained ≥ 7 years. Soft delete only. |
| **Timezone** | Every location carries an IANA timezone. All timestamps stored in UTC (`timestamptz`), rendered in location-local time. |
| **Money** | Stored as integer minor units (cents). Never floating point. Single currency (USD). |
| **Backups** | Nightly full backup + point-in-time recovery. Restore tested quarterly. |
| **Accessibility** | The customer-facing booking flow should meet WCAG 2.1 AA. |

---

## 7. Business Rules Index

| ID | Rule |
|---|---|
| BR-01 | Staff need ≥1 location and ≥1 service qualification to be schedulable |
| BR-02 | Offboarding is soft; no hard deletes |
| BR-03 | Shifts only at assigned locations |
| BR-04 | No overlapping shifts per staff, company-wide |
| BR-05 | Recurring patterns materialise on a rolling 8-week horizon |
| BR-06 | Approved time off blocks shifts and flags booked appointments |
| BR-07 | Appointment therapist must be qualified, on shift, and conflict-free |
| BR-08 | Appointment room must be active and conflict-free |
| BR-09 | Price is snapshotted at booking |
| BR-10 | Online booking respects lead time and horizon |
| BR-11 | Only completed appointments generate service revenue |
| BR-12 | Cancellation window determines cancelled vs late_cancelled |
| BR-13 | No-shows and late cancels increment a customer counter |
| BR-14 | Status transition is the only way to release a resource |
| BR-15 | Order is paid only when payments cover the total; no overpayment |
| BR-16 | SOAP notes are append-only |
| BR-17 | Payments are immutable; void and re-enter |
| BR-18 | Gift card balance derives from an append-only ledger |
| BR-19 | Gift card sale is a liability, not revenue |
| BR-20 | Purchaser and redeemer are separately recorded |
| BR-21 | Service-specific cards redeem only against their variant |
| BR-22 | Redemption cannot exceed remaining balance |
| BR-23 | Pay is based on published shift hours |
| BR-24 | Rates are effective-dated; history never changes |
| BR-25 | Locked pay periods are immutable |
| BR-26 | Prices are effective-dated, never edited in place |
| BR-27 | Catalogue items are deactivated, not deleted |
| BR-28 | Utilisation denominators are fixed as defined |
