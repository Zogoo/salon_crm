# Mongolian Massagelab — Business Analysis

**Version:** 1.1 · **Date:** 2026-09-01 · **Status:** For review, pre-implementation
**Source of truth:** `business_requirement.md` (FRS v7, 2026-08-21)

> **Delivery posture.** This is an **internal management platform** first. Release 1 is operated
> entirely by Owner, Manager and Therapist inside the four locations. Client self-service booking,
> online payment collection and online gift card purchase are specified in full here but deferred
> to Release 2 — see doc 06 §1. Rules affected by that deferral are marked **(Release 2)**.

---

## 1. Business Context

Mongolian Massagelab operates **four fixed locations** in the Chicago area:

| Location | Massage menu | Facial menu | Head spa / Bioelectric | Add-on price |
|---|---|---|---|---|
| **Lawrence** | Standard | Standard | — | $35 |
| **Skokie** | Standard | Standard | — | $35 |
| **Luma** | Standard | Extended (own menu) | Yes | $35 |
| **Belmont** | Premium (+$10–$40) | Premium | — | $40 |

All four operate in **US Central time (America/Chicago)**. The schedule day runs
**09:00 – 22:00**.

Revenue comes from massage, facial, head-spa and bioelectric services delivered by therapists in
rooms, plus add-ons, enhancements, gift card sales and a monthly membership subscription.

The scarce resources are:

1. **Therapist time** — a scheduled, on-shift therapist. Some services consume *two* therapists.
2. **Room time** — a physical room *of the right type* at that location.

Every appointment consumes exactly one room and **one or more** therapists simultaneously. This is
why the scheduling engine (doc 03) is the architectural centre of gravity.

### 1.1 Confirmed scope decisions

| Decision | Answer | Source |
|---|---|---|
| Locations | Exactly 4 — Lawrence, Skokie, Luma, Belmont | FRS §1, §16 |
| Timezone | US Central, all locations | FRS §25 |
| Roles | Owner, Manager (= front desk), Staff (therapist), Client | FRS §2 |
| Manager accounts | **One per location, 4 total**, scoped to that location | Owner decision |
| Therapist accounts | Up to **30 per location** | FRS §16 |
| Employment | Therapists are **1099 independent contractors** | FRS §18 |
| Therapist pay | **Per completed service line**, by session length (30/45/60/75/90/120 min) | FRS §4 |
| Manager pay | **Flat monthly rate**, not per session | FRS §4, §18 |
| Booking channels | Owner, Manager, walk-in · **client self-service online is Release 2** | FRS §5, §5.1, §21 |
| Payments in salon | **Recorded**, via the existing card terminal | FRS §21 |
| Payments online | **Processed via Stripe** — deposits, prepayment, fees, membership. **Release 2** | Owner decision |
| Payment methods | Card, Cash, Zelle, Online, Gift Card, Other | FRS §5, §7 |
| Split payment | Yes — one appointment across two methods | FRS §5, §21 |
| Deposit | 20% or full payment at online booking. **Release 2** | FRS §5.1 |
| No-show / late cancel | 20% fee; free ≥ 4 hours before. **Release 1 records the fee as owed; Release 2 charges it** | FRS §21 |
| Multi-therapist services | Appointment → 1..N therapists (couples, four hands, couple head spa) | Owner decision |
| Room matching | By **client capacity**, not strict type — the Skokie three-table room takes 1, 2 or 3 people. Head-spa rooms are exclusive to head-spa services | FRS §20 · Owner decision |
| Therapist pay on add-ons | Combined into one session when the total lands on a ladder rung, else split per item | Owner decision |
| Peak volume | **100 appointments per location per day**, 400 system-wide | Owner decision |
| Localisation | English only at launch — no bilingual requirement | Owner decision |
| Therapist payouts | The platform **reports** what is owed; it does not pay | Owner decision |
| Booking grid | 15-minute increments | FRS §5.1, §21 |
| Buffer | Minimum 15-minute gap, same room **and** same therapist | FRS §21 |
| Booking horizon | 6 months; cut-off configurable (15/30/60 min before start) | FRS §5.1, §21 |
| Gift cards | Sold in salon; cross-location redemption; flagged expired at 12 months but **balance never forfeited**. **Online purchase is Release 2** | FRS §12 · Owner decision |
| Membership | $80/month, one 60-min massage, rollover cap 3, 15-day cancellation notice, **tied to the joining location**. **Release 1 records the monthly payment by hand; Release 2 automates it** | FRS §23 · Owner decision |
| Client accounts | Required for self-service booking only. **Release 2** | FRS §22 |
| Notifications | Email **and** SMS: confirmation, **two reminders (24 h and 2 h)**, fee notice, low-rating alert | FRS §22 · Owner decision |
| Clinical records | **No** intake questionnaire, **no** consent form, **no** SOAP notes. Care logs kept — see §3.10 | Owner decision |
| Packages | **Removed from scope entirely** — not deferred | FRS §26 |
| Data migration | Existing client list + contact info + appointment history | FRS §24 |

---

## 2. Actors

| Actor | Description | Primary goals |
|---|---|---|
| **Owner** | The business owner. Access to all four locations. | Revenue, therapist earnings and payouts, utilisation, gift card liability, membership base |
| **Manager** | Front desk. **One account per location, scoped to that location.** | Book fast, run the day board, check in/out, take payment, sell gift cards, approve shift and therapist requests |
| **Staff (Therapist)** | 1099 contractor delivering the service. | See own schedule, request shift/location changes, see own earnings, read client preferences and care notes |
| **Client** | Buys and receives services. In Release 1 they are a record the staff maintain, not a user — they still receive notifications and leave ratings. Self-service arrives in Release 2. | Book online *(Release 2)*, manage bookings *(Release 2)*, buy/redeem gift cards, hold a membership, leave a rating |
| **System** | Non-human actor (scheduled jobs). | Send confirmations and reminders, charge fees, bill memberships, expire cards, close earning periods |

### 2.1 Access matrix (authoritative — FRS §2, §17)

| Capability | Owner | Manager | Staff |
|---|:--:|:--:|:--:|
| Switch between all 4 locations | ✓ | ✗ (1 location) | ✗ (request → Owner) |
| View schedule | ✓ all | ✓ own location | own only |
| Create appointment | ✓ | ✓ | **✗** |
| Add / edit client | ✓ | ✓ | ✗ |
| View / edit staff shifts | ✓ | ✓ | own, via request |
| Approve shift-change request | ✓ | ✓ | ✗ |
| **Approve location-change request** | ✓ | **✗** | ✗ |
| Approve specific-therapist request | ✓ | ✓ | ✗ |
| View staff pay rates | ✓ | ✗ | own only |
| View staff earnings | ✓ | ✗ | own only |
| Add / remove staff accounts, set rates | ✓ | ✗ | ✗ |
| Sell / view gift cards | ✓ | ✓ | **✗** |
| View owner financial reports | ✓ | ✗ | ✗ |
| Manage service menu | ✓ | ✗ | view; edit only if Owner grants |
| Manual earnings adjustment | ✓ | ✗ | ✗ |
| Read client preferences + care notes | ✓ | ✓ | own appointments only |

### 2.2 Separation-of-duties rules

Hard requirements, not preferences:

- **Manager must never see** `staff_rates`, earnings reports, payout statements, or any owner-only
  financial report. Manager is the front-desk role and sits in a public-facing area.
- **Staff see only their own** schedule, shift, rate and earnings — never another therapist's.
- **Manager is scoped to exactly one location** and cannot switch. Owner bypasses all scoping.
- **Only the Owner** may change a pay rate, adjust earnings manually, adjust a gift card balance,
  void a payment, issue a refund outside policy, or approve a staff location change. Every one of
  these writes an audit row.

---

## 3. Core Business Processes

### 3.1 Staff onboarding

1. Owner creates a **Staff** record: name, contact, 1099 contractor details, start date.
2. Owner assigns the **home location** (therapists work at one location at a time; changing it
   later is a request, see §3.3).
3. Owner assigns **service qualifications** — which services this therapist may perform.
   *A therapist can never be booked for a service they are not qualified for.*
4. Owner sets the **session rate ladder**: a rate for each of 30/45/60/75/90/120 minutes, with an
   `effective_from` date. Not every length is used by every menu — the ladder covers all six
   regardless (FRS §4).
5. System creates the account and sends an invitation.
6. Status → `active`; the therapist now appears in availability search.

For a **Manager**, step 4 is replaced by a single **flat monthly rate**.

**BR-01:** A staff member with no service qualifications or no location assignment cannot be
scheduled. Warn the Owner at onboarding completion.

### 3.2 Staff offboarding

1. Owner sets a **termination date**.
2. System **blocks** offboarding while future appointments are assigned to that therapist after the
   termination date, listing them for reassignment or cancellation.
3. Future shifts after the termination date are cancelled.
4. Status → `terminated`; login disabled.
5. Historical data — appointments, earnings lines, care notes, payouts — is **retained
   immutably**. It backs past payouts and client care.

**BR-02:** Offboarding is soft. No hard deletes of staff records, ever.

### 3.3 Shifts, shift-change requests and location-change requests

A shift record carries **staff, working date, start time, end time, working location, notes**
(FRS §3).

```
Staff                        Manager / Owner              System
  |                                |                          |
  |-- request shift change ------->|                          |
  |   (date, new start/end, note)  |                          |
  |                                |-- approve -------------->| shift updated
  |<-- notified -------------------|                          |
  |                                |                          |
  |-- request LOCATION change ---->|  (Manager cannot act)    |
  |                                |     Owner only --------->| home location updated
```

Two distinct concepts — keep them separate:

- **Request** = "I would like to work these hours / at this location." Staff-owned. Never
  authoritative.
- **Shift** = "You are working, at this location, these hours." Owner/Manager-owned. Drives
  **availability only** — not pay (see §3.8).

**BR-03:** A shift may only be created at the staff member's assigned location.
**BR-04:** Overlapping shifts for the same staff member are forbidden **across all four
locations** — a therapist cannot be on shift at Luma and Belmont simultaneously.
**BR-05:** Staff never self-edit a shift. A shift change is a request approved by Owner **or**
Manager.
**BR-06:** A **location**-change request may be approved **only by the Owner**. Manager cannot.
**BR-07:** Removing a therapist's availability for a date is blocked if appointments already sit
inside it; the system returns the conflicting list instead.

### 3.4 Booking an appointment

The same core transaction across all channels, with differences noted.

```
1. Identify client            → search by name/phone, or "Add New Client" inline
2. Choose service + length    → resolves to a ServiceVariant (+ optional add-ons/enhancements)
3. Choose location            → resolves the price and the room pool
4. Search availability        → engine returns bookable slots (doc 03)
   ├─ optional specific-therapist request
   └─ filtered by qualification, room type, and therapist count required
5. Select slot                → system holds room + therapist(s)
6. Confirm                    → Appointment created, prices snapshotted
   └─ if a specific therapist was requested → status `pending_approval`
7. Collect money (online only, Release 2) → 20% deposit or full payment via Stripe
8. Notify                     → email + SMS confirmation; reminder scheduled
```

**BR-08:** An appointment must reference therapist(s) who (a) are qualified for the service,
(b) have a shift covering the whole appointment at that location, and (c) have no overlapping
appointment **at any location**.
**BR-09:** An appointment must reference an active room at that location with no overlapping
appointment, whose **client capacity meets or exceeds** what the service needs, and which is not
reserved for a different specialism. A single massage may therefore run in a couple or three-table
room when the singles are full; a head-spa room accepts head-spa services only.
**BR-09a:** When several rooms qualify, the engine takes the **smallest sufficient** one, so a
couple room is not consumed by a one-person booking while a single room stands empty.
**BR-10:** A **minimum 15-minute gap** is required between consecutive appointments for the same
room *and* for the same therapist (FRS §21).
**BR-11:** The **price is snapshotted** at booking. Later menu changes never alter a booked or
completed appointment.
**BR-12** *(Release 2)***:** Client self-service bookings are offered on a **15-minute grid**, up
to **6 months** ahead, and close a configurable number of minutes before start (15 / 30 / 60).
**BR-13** *(Release 2)***:** In the client-facing flow the therapist roster is **never listed**. Default is "No
preference"; a client who wants a specific therapist types a name and selects from matches.
**BR-14:** An appointment may be created only by Owner or Manager, or by a Client for themselves.
Staff cannot create appointments.

#### Specific-therapist requests

A request for a named therapist — entered on the client's behalf or made by the client online —
**holds the slot** and requires **Owner or Manager approval** before confirmation. Clients are told
to expect confirmation within a few minutes.

**BR-15:** A specific-therapist request creates the appointment in `pending_approval`. It occupies
the room and therapist for conflict purposes from the moment it is created, so the slot cannot be
taken while approval is outstanding.
**BR-15a:** An unactioned request is held indefinitely and shown on both the Owner and Manager
dashboards with an **age counter**. After **45 minutes** with no human decision, the system
**auto-approves it** — but only if the requested therapist still has a published shift covering the
whole appointment and still has no conflict. If that check fails, the request stays pending and is
escalated rather than approved.

> Auto-approval is safe here precisely because the slot was already held. The request only exists
> because the engine found the therapist bookable, and the exclusion constraints have protected that
> slot ever since. The 45-minute re-check exists for the one case that can still change underneath
> it: someone editing the shift.
**BR-16:** If the requested therapist is in session or not working that day, the system offers
**that same therapist's next available time**. It never suggests a different therapist (FRS §5).

### 3.5 Appointment lifecycle

```
                       ┌───────────────────┐
                       │ pending_approval  │ ← specific-therapist request
                       └─────────┬─────────┘
                        approve  │  reject
                       ┌─────────▼─────────┐
                       │     scheduled     │ ← created (any channel)
                       └─────────┬─────────┘
        ┌────────────────┬───────┼────────────────┬──────────────────┐
        ▼                ▼       ▼                ▼                  ▼
 ┌────────────┐  ┌────────────┐ ┌──────────────┐ ┌───────────────┐  │
 │ checked_in │  │ cancelled  │ │ late_cancel  │ │   no_show     │  │
 └─────┬──────┘  └────────────┘ └──────────────┘ └───────────────┘  │
       ▼          (≥ 4h before)   (< 4h before)   (never arrived)   │
 ┌────────────┐    full refund     20% fee          20% fee         │
 │in_progress │                                                      │
 └─────┬──────┘                                                      │
       ▼                                                             │
 ┌────────────┐      ┌──────────┐      ┌───────────────────┐         │
 │ completed  │─────▶│   paid   │─────▶│ rating requested  │◀────────┘
 └────────────┘      └──────────┘      └───────────────────┘
```

**BR-17:** Only `completed` appointments generate **service revenue** and **therapist earnings**.
**BR-18:** `cancelled` vs `late_cancelled` is decided by the **4-hour** window measured from
`starts_at` in the location's timezone.
**BR-19:** A `no_show` or a cancellation inside 4 hours incurs a **20% fee** of the appointment
total (services + add-ons + enhancements, excluding tip). A cancellation 4 or more hours ahead is
**fee-free**.
**In Release 1** the fee is calculated and **recorded as an amount owed** — an open `Fee` order
line **visible on the client's profile only**. The front desk is deliberately *not* warned at the
next booking; nothing blocks or interrupts the booking flow. **In Release 2** it is taken from the
deposit or prepayment on file, and a fee-free cancellation is refunded in full.
**BR-20:** Every `no_show` and `late_cancelled` increments a counter on the client record. Owner
and Manager see this counter when booking that client again.
**BR-21:** Cancelling immediately frees the room and therapist(s). A status transition is the only
mechanism that releases a resource.

### 3.6 Check-in, service, checkout

1. Client arrives → Manager sets `checked_in`.
2. Therapist opens the appointment and reads the client's **preferences form** (areas to focus on,
   areas to avoid, pressure preference, other requests) and any prior **care notes**.
3. Therapist starts → `in_progress`.
4. Therapist finishes → `completed`, and may append a **care note** for the next session.
5. Manager opens the **Order**: service line(s) at snapshotted prices, add-ons, enhancements,
   membership entitlement applied if any, minus any deposit already taken.
6. Client pays the balance on the existing card terminal and is prompted to tip **20% / 25% / 30%
   / custom**.
7. Manager records the payment(s) — a single appointment may be settled across **two different
   methods** (e.g. part gift card, part card).
8. Order → `paid`. If the client paid by gift card, the card is redeemed automatically and the
   redemption is written to the Gift Card section.
9. Client is invited to rate the session — in-location touchscreen or SMS link tied to the
   therapist who performed the service.

**BR-22:** An order is `paid` only when `sum(payments) + sum(gift_card_redemptions) +
sum(membership_credits) >= total`. Overpayment is rejected; the difference must be entered as a tip.
**BR-23:** A payment record, once created, cannot be edited. It can only be **voided** (Owner) or
**refunded** (Owner, or by policy for a fee-free cancellation) and re-entered. Every void is
audit-logged.
**BR-24:** **Tips are recorded per appointment and attributed to the performing therapist(s).**
Where two therapists perform one appointment, the tip is split evenly unless overridden.

### 3.7 Gift card lifecycle

One product shape. Physical cards carry a printed barcode; online purchases are **fully digital**
and get a generated code that behaves identically for lookup and redemption.

```
issue (sold in salon or online) → active
   → partially redeemed (balance > 0) ─┐
   → fully redeemed (balance = 0)     ─┤→ closed
   → expired (12 months after sale)   ─┘   ← flag only; the balance stays spendable
```

**BR-25:** Gift card balance is **never a mutable column used as the source of truth**. It is
derived from an append-only ledger (issue, redeem, refund, adjust, expire). The `current_balance`
column is a maintained cache, reconciled nightly.
**BR-26:** Selling a gift card is **not revenue** — it is a **liability** (deferred revenue).
Revenue is recognised when the card is redeemed against a service. Reporting shows outstanding
gift card liability separately. This is the most common accounting error in salon systems.
**BR-27:** A gift card sale is **attributed to the selling location** for revenue reporting, while
the card itself is **visible and redeemable at all four locations** until the balance reaches $0
(FRS §12, §16).
**BR-28:** Buyer, recipient, seller, selling location, redeemer, redemption date, amount used,
remaining balance and the **associated appointment** are all recorded (FRS §13).
**BR-29:** Redeeming more than the remaining balance is rejected. The shortfall must be paid by
another method on the same order.
**BR-30:** Gift cards are flagged `expired` **12 months after purchase** (FRS §12), but an expired
card **keeps its full remaining balance and stays redeemable**. Expiry never forfeits value and
never writes a zeroing ledger entry. If the client returns after expiry and the service now costs
more than it did, they simply pay the difference — which is how a dollar-balance card behaves at
any time. `expiry_months` is configurable rather than hard-coded.

> Because no value is ever forfeited, the `expired` status is a **reporting and conversation flag**,
> not a financial event: it tells the Manager the card is old and lets the Owner see ageing
> liability. This also removes most of the legal exposure that a true expiry would carry — see
> RISK-01 in §8, now downgraded.
**BR-31:** Owner and Manager may sell and view gift cards. **Staff cannot.** Clients may buy them
online through their own account.

### 3.8 Therapist earnings and payout

Therapist pay is **piece rate on completed work**, not hours. Shifts do not pay.

1. Every **completed service line** writes an **earnings line**: therapist, date, location,
   duration bucket (30/45/60/75/90/120), rate applied, amount.
2. The rate applied is **the therapist's effective-dated rate for that duration on that service
   date** — never the current rate.
3. **Tips** are recorded per appointment and attributed to the therapist(s).
4. The Owner may **manually add session quantities and tips** for a therapist on a specific date,
   for corrections or off-system sessions (FRS §4). Every manual line is flagged and audit-logged.
5. The system totals per therapist per period — a specific date, week, month, custom range, and
   the two standing periods **1st–15th** and **16th–end of month** (FRS §8).
6. Owner reviews and **locks** the period. Locked periods are immutable; corrections flow into the
   next period as adjustments.

**BR-32:** Pay is computed from **completed service lines**, not from shift hours and not from
clock-in data. Idle shift time is unpaid — therapists are 1099 contractors.
**BR-33:** Therapist pay is computed on the appointment's **total delivered duration**, not on
each line separately. Sum the durations of all `service` and `add_on` items on the appointment:

- If the total **lands on a rung** of the ladder (30/45/60/75/90/120), the appointment produces
  **one** earning line at that rung. A 60-minute massage plus a 30-minute add-on is a single
  **90-minute** session paid at the 90-minute rate.
- If the total **has no rung** — a 120-minute massage plus a 30-minute add-on is 150 — it falls
  back to **one earning line per original item**, each at its own duration: a 120 and a 30.

The Staff Earnings quantity column (FRS §4, §8) counts whatever the rule produced: a 60+30 adds one
unit to the **90-minute** row, while a 150-minute total adds one unit to the 120 row and one to the
30 row.

> **This is a pay rule, not a pricing rule.** The client is always charged per menu item — the
> 60-minute massage at its price plus the add-on at $35 or $40. Only the therapist's earning is
> combined. Note also that combining usually pays *less* than two separate lines would (a 90-minute
> rate is normally below a 60 plus a 30), which is the intended effect: one continuous 90-minute
> session is one 90-minute session.
**BR-34:** Where an appointment has two therapists (couples, four hands, couple head spa), **each
therapist earns their own full session rate** for that duration.
**BR-35:** Rates are **effective-dated**. Historical earnings never change when a rate is updated
going forward.
**BR-36:** Managers are on a **flat monthly rate** and never produce per-session earnings lines.
**BR-37:** Once an earnings period is locked, its lines are read-only.

### 3.9 Membership

A monthly subscription, billed by Stripe.

| Attribute | Value |
|---|---|
| Price | **$80 / month** |
| Included | One **60-minute** massage per cycle: deep tissue, Swedish or sport (member's choice) |
| Complimentary with it | Hot stone, hot herbal compression, aromatherapy — no extra charge (non-members pay **$15 each**; none adds time to the session) |
| Upgrade | Member may pay the **difference** to take pregnancy, lymphatic or another service instead |
| Rollover | Unused sessions roll over, **capped at 3 accumulated** |
| Cancellation | Requires **≥ 15 days notice** before the next renewal date |
| **Location** | **Tied to the location the member joined at.** Using it elsewhere is not self-service — it needs Owner or Manager arrangement |
| Reminders | **None** — no renewal reminder, no cancellation-window reminder (FRS §22) |

**BR-38:** Each successful monthly payment grants **one credit** — recorded by hand in Release 1,
billed by Stripe in Release 2. Credit balance is capped at 3;
a charge that would exceed the cap grants nothing and is recorded as forfeited-to-cap.
**BR-39:** Redeeming a credit against the included 60-minute massage costs the member $0. Choosing
a different service **consumes the credit** and charges the **difference** between that service's
list price and the included 60-minute massage's list price, both taken **at the redeeming location
on the day of the visit**.
**BR-39a:** A membership is **scoped to the location where the member enrolled**. Redeeming a
credit at another location is rejected in the normal flow and requires an explicit **Owner or
Manager override**, which is recorded on the credit transaction with the approver's identity.

> **Note the deliberate asymmetry with gift cards.** A gift card is company-wide and redeemable
> anywhere (BR-27); a membership is not. Members are attached to a home location and its therapists,
> and the entitlement is priced against that location's menu — Belmont's prices run $10–$40 above
> the others, so a Belmont-priced $80 entitlement redeemed at Lawrence would be worth more than it
> was sold for. The override exists for the genuine one-off; it is not a switch the member controls.
**BR-40:** A cancellation request submitted fewer than 15 days before renewal takes effect **after**
the next renewal, not immediately. The next charge still occurs.
**BR-41:** Membership credits are a **liability** in the same sense as gift cards — recognised as
revenue when redeemed, not when billed.

### 3.10 Client management, preferences and feedback

Each client profile carries name, phone, email, date of birth, appointment history, services
received, therapists seen, notes, gift cards bought or received, cancellation history, no-show
history, per-appointment ratings, and the preferences form (FRS §11).

**Preferences form** (FRS §11.1) — "Areas to Pay More Attention To", "Areas to Avoid", "Pressure
Preference" (Light / Medium / Firm), "Other Requests / Notes". Saved on the client profile, shown
to the assigned therapist before the session, updatable whenever the client gives new information.
This is the **Form** field on the New Appointment screen.

**Care notes** — a therapist's short, per-session log of what to avoid, what needed attention, and
anything to consider next time. Deliberately **not** a clinical record: there is no health questionnaire, no consent signature, and no SOAP structure. It is still
body-related information about an identifiable person, so it is encrypted at rest, restricted to
Owner, Manager and the assigned therapist, and append-only.

**Post-service rating** (FRS §11.2) — after `completed`, the client rates **1–10**, optionally
writes feedback, and optionally answers "What could we improve?" and "Would you recommend us?"
(Yes/No). Collected on an in-location touchscreen or via an SMS link **tied to the therapist who
performed the service**. Saved per appointment, shown in the client's profile history.

**Low-rating alert.** A score at or below a configurable threshold notifies **both the Owner and
that location's Manager** immediately. The threshold is a per-location setting defaulting to
**6 or below** on the 1–10 scale; FRS v7 sets no number, so this default is ours and is trivial to
change.

**BR-42:** A client profile is **company-wide** across all four locations — one client, one
history, regardless of which location they visit.
**BR-43:** The preferences form is current-state with a version history; updating it never
destroys the previous answers.
**BR-44:** Care notes are **append-only**. A correction is a new note referencing the original.
**BR-45:** One rating per appointment, always linked to both the appointment and the therapist.
**BR-45a:** A rating at or below the location's alert threshold notifies the Owner **and** that
location's Manager. The alert names the appointment and therapist; it is not anonymised.
**BR-46:** Every `completed` appointment is automatically appended to the client's visit history.
**BR-47:** Clients need an account **only** for self-service booking, which is Release 2. In
Release 1 no client has an account; Owner and Manager book on their behalf throughout.

---

## 4. End-to-End Scenario Walkthroughs

### 4.1 Phone booking with a specific therapist request

> A client calls Skokie. Wants a 90-minute deep tissue on Saturday afternoon, and asks for Anna.

1. Manager searches by phone → finds the client, sees 6 prior visits, pressure preference "Firm",
   "avoid lower back", `no_show_count` 0, and an active membership with 2 rolled-over credits.
2. Selects **Deep Tissue / 90 min**, Skokie, Saturday. Price resolves to **$115**.
3. Filters to **Anna**. Engine returns Anna's free slots where a Skokie single room is also free
   with a 15-minute gap either side: 13:00, 15:30.
4. Client takes 15:30. Manager enters it as a **specific therapist request**.
5. Appointment is created `pending_approval`, already holding Anna and the room.
6. Manager approves it on the spot → `scheduled`. Confirmation email + SMS go out; a reminder is
   scheduled.
7. Manager applies a membership credit; the member owes the difference between $115 and the
   included 60-min price of $80 → **$35**.

**Failure case designed for:** the Skokie manager and an online client both commit Anna's 15:30
within the same 200 ms. See doc 03 §4 — prevented at the database level, not in application code.

### 4.2 Client self-service booking online *(Release 2)*

1. Client signs in to their account (required — FRS §5.1) and picks service, length, location, date.
2. Therapist field defaults to **"No preference."** If they want someone specific, they **type a
   name**; the system matches as they type. The roster is never listed.
3. Engine returns times on a **15-minute grid**, up to 6 months out, stopping N minutes before
   start per the Owner's cut-off setting.
4. Client picks a slot; the system places a **short-lived hold** so it survives checkout.
5. Client optionally leaves a **note for their therapist**.
6. Client chooses **20% deposit** or **full payment**; Stripe captures it.
7. Appointment created — `scheduled`, or `pending_approval` if a therapist was named.
8. **Email and SMS** confirmation sent.

### 4.3 Walk-in

1. Manager searches availability for **now → next 30 minutes** at this location only.
2. Engine returns therapist/room pairs free right now, respecting the 15-minute buffer.
3. Manager books, checks in, and proceeds in one action. No deposit — payment is at checkout.

> **Note on FRS §3 and §21.** Both read as though *staff* may add a walk-in, while FRS §2 states
> twice that staff cannot create appointments. §2 governs: **only Owner and Manager enter a
> walk-in**, and staff have no appointment-creation permission of any kind. The wording in §3 and
> §21 describes who is standing at the desk, not who holds the permission.

### 4.4 Couples massage

1. Two clients book a **90-minute couples massage** at Luma — $230.
2. Engine requires a **couple room** and **two qualified therapists**, both free for the whole
   interval with the 15-minute buffer.
3. One appointment is created: one room, two therapists, two client participants.
4. On completion, **each therapist earns their own 90-minute rate**; the tip is split evenly
   unless the Manager overrides the split.

### 4.5 Semi-monthly earnings close

1. On the 16th, the system closes the 1st–15th period and totals each therapist's session
   quantities by duration, service earnings, tips and total.
2. Owner reviews, adds any manual session or tip corrections, and resolves exceptions.
3. Payout statements generated using the effective-dated rates that applied on each service date.
4. Owner locks the period.

---

## 5. Reporting Requirements

| Report | Contents | Model implication | FRS |
|---|---|---|---|
| **Owner dashboard** | Today's appointments, completed, revenue, tips, staff working / not working, available rooms, gift cards sold and redeemed — for the selected location and date | Needs live day-scoped aggregates, no warehouse | §15 |
| **Staff earnings** | Per therapist per period: quantity and earnings for each of 30/45/60/75/90/120, tips, total. Date, week, month, custom range, **plus 1st–15th and 16th–EOM** | Requires per-service-line earnings rows with a snapshotted rate | §4, §8 |
| **Client log** | Every completed appointment for a date: time, client, therapist, service, length, price, tip, total paid, method | Requires immutable appointment + order history | §9 |
| **Daily revenue** | Card, Cash, Zelle, Online, Other, Tips, Total — by date, week, month, custom range | Requires payment-method breakdown, gift card liability excluded | §10 |
| **Gift card liability** | Outstanding balance by issue month and **selling location** | Requires the ledger and selling-location attribution | §12, §16 |
| **Membership** | Active members, credits outstanding, rollover at cap, upgrades, cancellations pending | Requires the credit ledger | §23 |
| **Ratings** | Average and distribution per therapist, per location, per period; recommend rate | Requires per-appointment ratings | §11.2 |
| **Cross-location roll-up** | Owner-level reports combining all four locations | Owner scope bypasses location filtering | §16 |

**BR-48:** Service revenue comes from **completed** appointments' service lines. Gift card sales
and membership billings are **liabilities**, reported separately. No-show and late-cancellation
fees are their own revenue category — neither service revenue nor a liability.

---

## 6. Non-Functional Requirements

| Area | Requirement |
|---|---|
| **Availability** | Business-hours critical. Target 99.5%, with a printable daily schedule fallback per location. |
| **Performance** | Availability search < 500 ms for a 7-day window at one location. Booking flow < 3 seconds end to end. |
| **Concurrency** | Zero tolerance for double-booking a room or a therapist. Enforced by database constraint, not application code. |
| **Scale** | 4 locations × up to 30 therapists = 120 therapist accounts, 4 manager accounts, 1 owner. ~28 rooms total. |
| **Data protection** | Care notes and preference forms are encrypted at rest and access-controlled. Card data never touches our servers (Stripe Elements / SetupIntent). |
| **PCI** | **SAQ-A only.** Online card data is tokenised client-side by Stripe. In-salon card payments run on the existing terminal and are only *recorded*. |
| **Auditability** | All changes to rates, earnings, payments, refunds, gift card balances, membership state, appointment status and locked periods are audit-logged with actor, timestamp, before/after. |
| **Retention** | Financial records ≥ 7 years. Soft delete only. |
| **Timezone** | All four locations are `America/Chicago`. Timestamps stored UTC (`timestamptz`), rendered in Central. The per-location timezone column stays — it costs nothing and removes a migration if a location opens elsewhere. |
| **Money** | Integer minor units (cents). Never floating point. USD only. |
| **Localisation** | English UI in v1. Mongolian/Spanish are plausible later — keep all user-facing strings in i18n files from day one. |
| **Backups** | Nightly full backup + point-in-time recovery. Restore tested quarterly. |
| **Accessibility** | Client-facing booking flow and the in-location rating screen meet WCAG 2.1 AA. |
| **SMS** | Transactional only (confirmation, reminder, fee notice, rating link). Opt-out honoured; no marketing SMS without separate consent. |

---

## 7. Business Rules Index

| ID | Rule |
|---|---|
| BR-01 | Staff need a location and ≥1 qualification to be schedulable |
| BR-02 | Offboarding is soft; no hard deletes |
| BR-03 | Shifts only at the staff member's assigned location |
| BR-04 | No overlapping shifts per staff, across all four locations |
| BR-05 | Staff never self-edit shifts; changes are approved by Owner or Manager |
| BR-06 | Location-change requests are approved by the **Owner only** |
| BR-07 | Removing availability is blocked when appointments sit inside it |
| BR-08 | Appointment therapists must be qualified, on shift, and conflict-free company-wide |
| BR-09 | Appointment room must be active, at the location, and of sufficient capacity |
| BR-09a | The smallest sufficient room wins when several qualify |
| BR-10 | Minimum 15-minute gap between appointments, same room and same therapist |
| BR-11 | Price is snapshotted at booking |
| BR-12 | Client booking: 15-min grid, 6-month horizon, configurable cut-off |
| BR-13 | Client-facing therapist selection is search-only; roster never listed |
| BR-14 | Only Owner, Manager or the Client themselves create appointments |
| BR-15 | Specific-therapist request holds the slot as `pending_approval` |
| BR-15a | Unactioned requests auto-approve after 45 min if the therapist is still free |
| BR-16 | Unavailable requested therapist → that therapist's next available time only |
| BR-17 | Only completed appointments generate service revenue and earnings |
| BR-18 | 4-hour window decides `cancelled` vs `late_cancelled` |
| BR-19 | No-show or late cancel = 20% fee; ≥4h cancel = full refund |
| BR-20 | No-shows and late cancels increment client counters |
| BR-21 | Status transition is the only way to release a resource |
| BR-22 | Order settles only when payments + redemptions + credits cover the total |
| BR-23 | Payments are immutable; void or refund and re-enter |
| BR-24 | Tips are recorded per appointment and attributed to the therapist(s) |
| BR-25 | Gift card balance derives from an append-only ledger |
| BR-26 | Gift card sale is a liability, not revenue |
| BR-27 | Sale attributed to selling location; redeemable at all four |
| BR-28 | Buyer, recipient, redeemer and redeeming appointment all recorded |
| BR-29 | Redemption cannot exceed remaining balance |
| BR-30 | Expiry flags the card at 12 months but never forfeits the balance |
| BR-31 | Staff cannot view or sell gift cards |
| BR-32 | Pay is per completed service line, not per shift hour |
| BR-33 | Pay is on total delivered duration when it lands on a ladder rung, else per item |
| BR-34 | Two-therapist services pay each therapist a full session rate |
| BR-35 | Rates are effective-dated; history never changes |
| BR-36 | Managers are on a flat monthly rate, no session earnings |
| BR-37 | Locked earnings periods are immutable |
| BR-38 | Membership grants 1 credit per charge, capped at 3 accumulated |
| BR-39 | Upgrades consume the credit and charge the price difference on the day |
| BR-39a | A membership is scoped to its joining location; cross-location use needs an override |
| BR-40 | Cancellation needs ≥15 days notice; otherwise it takes effect after the next renewal |
| BR-41 | Membership billings are a liability until the credit is redeemed |
| BR-42 | Client profiles are company-wide across all four locations |
| BR-43 | Preference form is versioned, never destructively overwritten |
| BR-44 | Care notes are append-only |
| BR-45 | One rating per appointment, linked to the therapist |
| BR-45a | Ratings at or below the threshold alert Owner and location Manager |
| BR-46 | Completed appointments append to client visit history |
| BR-47 | Client accounts are required only for self-service booking |
| BR-48 | Revenue, liabilities and fees are three separate reporting categories |

---

## 8. Risks Raised by This Specification

| ID | Risk | Detail |
|---|---|---|
| **RISK-01** | **Gift card expiry wording** | An expired card **keeps its balance and stays redeemable** — the client pays only the difference if prices have moved (BR-30). Because nothing is forfeited, the CARD Act's five-year floor and the Illinois gift-certificate provisions, which are chiefly about *funds being forfeited*, largely do not bite. What remains is presentational: never describe a card as "expired" to a customer in a way that implies the money is gone. Worth a short check with counsel on the wording printed on the card and shown at redemption. Not a design risk. |
| **RISK-02** | Automatic fee charging | Auto-charging a stored card for a no-show requires the client to have agreed to it at booking. The booking flow must capture explicit consent to the cancellation policy, stored with a timestamp, before the card is saved for future use. Stripe requires this for off-session charges regardless. |
| **RISK-03** | SMS consent | Transactional SMS to a client who booked is generally fine; the rating-request SMS sits closer to the line. Capture SMS consent at account creation and honour STOP. |
| **RISK-04** | Contractor classification | Therapists are 1099 contractors, but the platform assigns their shifts, sets their rates and controls their client allocation. That is a worker-classification question the software cannot solve; noted so it is a decision rather than an oversight. |
