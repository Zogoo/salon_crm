# Delivery Roadmap, Assumptions & Open Questions

**Version:** 1.0 · Read §3 before any implementation begins.
**Aligned to:** FRS v7

> FRS v7 §26 states that all open items are resolved. That is true of the **business** questions —
> membership price, rollover cap, notifications and authentication are all settled. What follows
> are the **implementation** questions v7 does not reach, plus two places where v7 contradicts
> itself.

---

## 1. Phased Delivery

### Delivery posture: internal first

This platform is, at this stage, **an internal management tool**. Everything in Release 1 is
operated by an Owner, a Manager or a Therapist standing in one of the four locations. Nothing in it
requires a client to log in, open a browser, or enter a card.

That decision defers three things that FRS v7 describes and that this design fully specifies:
client self-service booking (§5.1), online payment collection — deposits, prepayment and automatic
no-show fees (§5.1, §21) — and online gift card purchase (§12). They remain designed, modelled and
documented throughout these six documents; they are simply not built first.

**What deferring them costs, stated plainly.** Two business rules degrade in Release 1:

| Rule | Release 1 behaviour | Release 2 behaviour |
|---|---|---|
| Deposits at booking (FRS §5.1) | Not taken — bookings are internal and paid at checkout | 20% or full payment via Stripe |
| No-show / late-cancel fee (BR-19) | **Calculated and recorded as owed**, not charged. The 4-hour window still runs; the fee becomes an open `Fee` order line surfaced to the Manager at the client's next booking | Charged automatically against the saved card |
| Membership billing (BR-38) | Enrolment, credits, rollover cap and the 15-day notice all work; the **$80 monthly payment is recorded by hand** like any other payment | Stripe subscription bills automatically |

Everything else — the scheduling core, earnings, gift cards, reporting — is complete in Release 1.

The sequencing principle within each release: **build the resource-scheduling core first and
correctly**, because everything else (earnings, revenue, ratings, membership redemption) is derived
from appointment data. A wrong scheduling model is the only mistake here that cannot be patched
later.

---

## Release 1 — Internal management platform

### Phase 0 — Foundations (1–2 weeks)

- Rails app, Postgres 16 with `btree_gist` / `pg_trgm` / `citext`, Vite Ruby + the **console and
  kiosk** AngularJS shells (the client bundle is Release 2)
- Users and the three staff roles; staff sessions; TOTP for Owner
- Pundit skeleton with `verify_authorized` enforced from the first controller
- **Seed the four locations, their business hours, and all 28 typed rooms** (FRS §20)
- Audit log infrastructure
- CI pipeline, staging deploy, backup + restore drill

**Exit criteria:** the Owner can log in, switch between all four locations, and see the correct
room inventory at each; a Manager can log in and cannot switch. The restore runbook has been
executed successfully once.

### Phase 1 — Scheduling core (4–5 weeks) — *the critical phase*

- Service catalogue: services, variants, durations, `therapist_count`, allowed room types,
  add-ons, enhancements, effective-dated location prices
- **Seed the full menu for all four locations** from FRS §19.2–§19.11
- Staff profiles, qualifications, the six-rung session rate ladder, manager monthly rates
- Shifts, shift breaks, and the `staff_requests` approval workflow (including the owner-only
  location-change rule)
- **Availability search engine** (doc 03) including multi-therapist and room-type matching
- **Appointments with both exclusion constraints and the `appointment_staff` trigger** (doc 03 §4)
- Specific-therapist requests: `pending_approval`, the approval queue, next-available-time
- Day board: rooms × time, 09:00–22:00
- Appointment lifecycle transitions; walk-ins
- Client records, phone search, "Add New Client", merge tool

**Exit criteria:** the eighteen Release 1 scheduling tests in doc 03 §6.1 pass. Tests 1, 11, 12 and
16 — concurrency, couples cardinality, atomic two-therapist rollback, and the 15-minute gap — gate
the phase. Do not proceed until they are green.

### Phase 2 — Money and operations (2–3 weeks)

- Orders, line items, discounts, the `revenue_category` classification
- Payments: **recorded** methods only — card terminal, cash, Zelle, gift card, other — and split
  payment across two methods
- Tips, including the two-therapist split
- Cancellation and no-show policy: the 4-hour window and the 20% calculation, **recorded as an
  amount owed** rather than charged
- Gift cards: physical cards with barcode lookup, the ledger, cross-location redemption,
  reconciliation job
- Client preferences form (versioned) and care notes (append-only, encrypted)
- Email + SMS notifications: confirmation, reminder, approval decisions, fee notice
- Ratings: the in-location kiosk and the SMS rating link (neither needs a client account)

**Exit criteria:** a full day can be operated end to end at one location — book, confirm, check in,
serve, note, pay with a split across two methods, close, rate. The gift card ledger reconciles to
zero drift. A no-show produces a correctly calculated open fee that appears when that client is
next booked.

### Phase 3 — Earnings, membership and reporting (3–4 weeks)

- `earning_lines` generated on appointment completion, with rate snapshotting
- Manual session and tip entry (Owner)
- Semi-monthly period generation, statements, adjustments, locking
- Membership: enrolment, the credit ledger with the 3-credit cap, redemption against the included
  60-minute massage, upgrade pricing, the 15-day cancellation rule — **billed by recording the
  monthly payment manually**
- Owner dashboard (FRS §15)
- Daily revenue report (FRS §10), client log (FRS §9), staff earnings report (FRS §4, §8)
- Gift card liability and membership reports
- XLSX / PDF export pipeline

**Exit criteria:** one historical half-month closes correctly and a therapist's total reconciles by
hand against their completed appointments. Revenue, liabilities and fees appear as three separate
figures and never as one. A member accrues credits to the cap, redeems one at $0, and redeems one
against a lymphatic massage paying only the difference.

### Phase 4 — Data migration and go-live (1–2 weeks)

- Import the existing client list: contact information and appointment history (FRS §24)
- **Import any outstanding gift cards with correct balances** — unrecorded liability is the
  expensive failure mode here
- Parallel-run one location for a week before switching the rest
- Train the four Managers; print the fallback day sheets

**Release 1 total: roughly 11–15 weeks** of focused work, excluding UI design and UAT.

---

## Release 2 — Client-facing (designed, not scheduled)

Not committed to a date. Each phase is independently shippable, and Phase 5 can ship without Phase
6 if you want online booking without online payment — bookings would then be paid at the salon
exactly as an internally-booked one is.

### Phase 5 — Client accounts and self-service booking (3–4 weeks)

- Client accounts: registration, SMS-code login, profile
- The client AngularJS bundle (doc 04 §2.3)
- Public booking: service → location → date → slot → therapist **search** → confirm
- The 15-minute grid, 6-month horizon and configurable booking cut-off on the client channel
- Slot holds across the checkout step
- My bookings, self-service cancellation with the fee rule applied
- Rate limiting, bot protection, and the roster-privacy guarantees (BR-13)

**Exit criteria:** a client can register, book, receive email **and** SMS confirmation, and cancel
outside the window. A penetration attempt cannot enumerate the therapist roster through any public
endpoint.

### Phase 6 — Online payment (2–3 weeks)

- Stripe: PaymentIntents, deposits and full prepayment at booking
- Saved cards with recorded cancellation-policy consent (RISK-02)
- Off-session automatic no-show and late-cancellation fee charges, replacing Release 1's
  amount-owed behaviour
- Refunds, including the full refund on a fee-free cancellation and on a rejected therapist request
- Digital gift card purchase online
- Webhook handling, idempotent by event id

**Exit criteria:** a 20% deposit is captured at booking, a no-show fee charges correctly against a
saved card in Stripe test mode, and a ≥4-hour cancellation refunds in full.

### Phase 7 — Membership billing automation (1 week)

- Stripe Subscriptions at $80/month replacing manual monthly recording
- `invoice.paid` → credit grant; `invoice.payment_failed` → `past_due`
- Scheduled cancellation at the date the 15-day rule produced

**Exit criteria:** a membership bills, grants and caps credits without anyone touching it, and a
cancellation requested 14 days before renewal takes effect after the *following* period.

**Release 2 total: roughly 6–8 weeks.**

---

## 2. Assumptions Made

FRS v7 is unusually complete, so this list is short. Each of these is a default I have chosen
where the spec is silent — cheap to change **now** and expensive to change after its phase.

| # | Assumption | Impact if wrong |
|---|---|---|
| **A-01** | **An add-on is a 30-minute service line on the same appointment, delivered by the same therapist, extending total duration.** A 60-min massage + scalp add-on occupies 90 minutes plus buffer. | **High.** If add-ons are meant to run *within* the base duration, every duration calculation and every price is wrong. |
| **A-02** | An **enhancement** (essential oil, $10) adds price but **no duration and no therapist pay**. | Low |
| **A-03** | **Each service line earns at its own duration bucket.** A 60 + 30 appointment produces a 60-minute earning line and a 30-minute earning line, not a single 90-minute one. | **High** — changes every earnings figure. See OQ-01. |
| **A-04** | A membership **upgrade** charges the difference between the chosen service's list price at that location and the included 60-minute massage's list price at that location. | Medium — see OQ-03 |
| **A-05** | **Tips go 100% to the performing therapist**, split evenly between two therapists on a couples or four-hands appointment unless overridden. | Medium |
| **A-06** | **Sales tax is out of scope.** Illinois generally does not tax massage services, and gift cards are not taxed at sale. A `tax_cents` column exists and is always 0. | Medium — per-state rules if wrong |
| **A-07** | The **deposit and fee base** is the appointment total (services + add-ons + enhancements), **excluding tip**. Release 1 calculates the fee and records it as owed; Release 2 charges it. | Low |
| **A-08** | **The buffer trails the appointment** rather than surrounding it, producing exactly one 15-minute gap between consecutive bookings. | Low — but see doc 03 §1.1 |
| **A-09** | A **three-table room** at Skokie is bookable by any service needing 1–3 tables; nothing in FRS v7 describes a three-person service, so it currently serves as an overflow single/couple room. | Low — see OQ-06 |
| **A-10** | **Single head spa runs in a head-spa room** (Luma has 2, both described as "head-spa couple rooms"). | Low |
| **A-11** | **Client accounts are company-wide**, as are client profiles, gift cards and memberships. | Low |
| **A-12** | **Walk-ins are entered by Owner or Manager**, not Staff — following FRS §2 over FRS §3/§21. | Medium — see OQ-02 |
| **A-13** | **A membership credit may be redeemed at any of the four locations.** | Low |
| **A-14** | **Reminder timing is 24 hours before start.** FRS §22 requires a reminder but gives no timing. | Low — see OQ-05 |
| **A-18** | **Membership is billed by hand in Release 1** — the Manager records the $80 like any other payment, and the credit grant is triggered by that recorded payment rather than by a Stripe webhook. | Medium — operationally manual until Release 2 Phase 7 |
| **A-19** | **Notifications ship in Release 1.** Confirmations, reminders, fee notices and rating links need no client account, only a phone number and an email address on the client record. | Low — could be deferred if SMS cost is a concern |
| **A-15** | Data retention **7 years**, soft delete only. | Low |
| **A-16** | **English UI in v1**, with all strings in i18n files so Mongolian or Spanish is additive. | Low |
| **A-18** | **Membership is billed by hand in Release 1** — the Manager records the $80 like any other payment, and the credit grant is triggered by that recorded payment rather than by a Stripe webhook. | Medium — manual until Release 2 Phase 7 |
| **A-19** | **Notifications ship in Release 1.** Confirmations, reminders, fee notices and rating links need no client account — only a phone number and an email address on the client record. | Low — deferrable if SMS cost is a concern |
| **A-17** | **A therapist works at one location at a time**; the location-change request moves them, it does not add a second location. | Medium — many-to-many would change the shift and availability model |

---

## 3. Open Questions — Please Answer Before Implementation

Ordered by blast radius. **OQ-01 and OQ-02 should be answered before Phase 1 starts.**

### Blocking

**OQ-01 — How does an add-on pay the therapist?**
FRS §4 pays by session length, and FRS §19.9–§19.10 sell 30-minute add-ons. If a client books a
60-minute massage plus a 30-minute scalp add-on, does the therapist earn (a) the 60 rate **plus**
the 30 rate — two lines, which is what A-03 assumes and what makes the §8 quantity table add up —
or (b) a single 90-minute rate for a 90-minute booking? These produce different totals, and the
choice also decides what the "quantity" column in the earnings report counts. Related: what happens
above 120 minutes, since the ladder stops there — a 120-minute massage plus a 30-minute add-on has
no 150 rung.

**OQ-02 — Can Staff enter a walk-in, or not?**
FRS §2 says twice, marked *confirmed*, that Staff cannot create appointments. FRS §3 and §21 say
Staff can add a walk-in client directly into the schedule. These cannot both be true. The docs
currently follow §2 (assumption A-12). If Staff genuinely need to add walk-ins, that is a narrow
carve-out in the permission model — creating an appointment starting now, at their own location,
assigned to themselves — not a general booking permission.

### Important (answer before their phase)

**OQ-03 — How is a membership upgrade priced?** *(Release 1, Phase 3)*
FRS §23 says a member "can pay extra" for a different service. Is the extra (a) the difference
between the two list prices at that location (A-04), (b) the difference from the $80 membership
price, or (c) a fixed upgrade fee? Also: does an upgrade consume the monthly credit, or is it
charged in full and the credit preserved?

**OQ-04 — What happens to a therapist request nobody approves?** *(Release 1)*
FRS §5 promises the client confirmation "within a few minutes" but does not say what happens if no
Owner or Manager acts. The slot is held meanwhile, so an unattended request blocks inventory.
Options: auto-approve after N minutes, auto-reject and refund after N minutes, or hold indefinitely
with an escalating alert. Currently: held indefinitely, surfaced on both dashboards with an age
counter.

**OQ-05 — Reminder timing.** FRS §22 requires an appointment reminder but not when. 24 hours is
assumed. Do you want a second, shorter one — 2 hours is the standard second touch and measurably
reduces no-shows, which now cost you a 20% fee collection rather than just an empty room.

**OQ-06 — What is the Skokie three-table room for?**
FRS §20 lists it but no service in FRS §19 needs three tables. Is there a three-person service, is
it an overflow room, or is it for training?

**OQ-07 — Complimentary membership extras are not on the menu.**
FRS §23 includes hot stone, hot herbal compression and aromatherapy free with the membership
massage. None of the three appears in the FRS §19 menus, and only essential oil ($10) exists as an
enhancement. What do non-members pay for hot stone, hot herbal compression and aromatherapy, and do
any of them add time to the session?

**OQ-08 — Are the four Managers the only front-desk accounts?**
Confirmed: one Manager account per location. In practice a front desk is staffed across a 09:00–
22:00 day, likely by more than one person sharing one login. A shared login means the audit log
cannot say who took a payment or approved a request. Worth deciding whether that matters to you
before go-live; adding more Manager accounts later is trivial, but retrofitting attribution to
past records is not.

**OQ-09 — Gift card expiry.** *(Release 1)* See RISK-01 in doc 01 §8. FRS §12 sets 12 months. The federal CARD
Act sets a five-year floor for the funds behind most gift certificates, and Illinois has its own
provisions. The system implements expiry as a configurable value so the policy is yours to set —
but please confirm the 12-month figure with counsel before it is switched on, because the exposure
is a claim from a cardholder, not a bug.

**OQ-10 — Who receives the money?** *(Release 1, Phase 3)* Therapists are 1099 contractors earning
per session. Does the platform need to **pay them** (ACH, a payout file), or does it only need to
**report** what is owed so payment happens outside the system? These documents assume reporting
only. Actual payouts are a substantially larger piece of work — and note that Release 1 has no
payment gateway at all, so building payouts would pull one in.

**OQ-11 — How should an unpaid no-show fee behave at the next booking?** *(Release 1, Phase 2)*
Without a gateway, a fee is an amount owed rather than a charge. When that client books again, does
the Manager (a) see a warning and collect at checkout, (b) get blocked from booking until it is
settled, or (c) see it only on the client profile? Option (a) is assumed. This question disappears
in Release 2, when the fee is charged automatically.

### Nice to resolve

**OQ-12 — Rating follow-up.** Ratings are collected but FRS v7 does not say what happens to a low
one. Should a score below some threshold alert the Owner or the location Manager?

**OQ-13 — Can a client rebook the same therapist directly?** *(Release 2)*
The roster is deliberately unbrowsable, but a returning client already knows who they saw. Should
"book again with Anna" appear on their own visit history? It leaks no one else's identity and is
the single highest-value convenience in the client app.

**OQ-14 — Expected volume.** Roughly how many appointments per location per day? This validates the
single-server sizing and the availability-search budget. The estimates in doc 03 §2.2 assume ~20
per location per day.

**OQ-15 — Branding and existing website.** Is there a site the booking flow must match or embed
into?

**OQ-16 — Does anything need to be bilingual at launch** — the client booking flow, the rating
screen, or the staff console?

---

## 4. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-booking under concurrent front-desk and online booking | High without care | Severe | Postgres exclusion constraints on `appointments` **and** `appointment_staff` (doc 03 §4) — designed out, not tested out |
| **Half-created two-therapist appointment** | Medium | Severe (couples booking with one therapist) | Both `appointment_staff` rows inside one transaction; test 12 gates Phase 1 |
| **`appointment_staff` drifting from its parent** | Low | Severe (silent double-booking) | Trigger + nightly `VerifyAppointmentStaffSyncJob` |
| Gift card liability misreported as revenue | High (very common) | Severe (overstated profit, tax exposure) | `revenue_category` on every line item; liability report in Phase 3 |
| **Membership credits misreported as revenue** | High | Severe | Same mechanism — membership billing is a liability until the credit is redeemed |
| **12-month gift card expiry unenforceable** | Medium | High (legal claim, refund exposure) | Configurable expiry, expiry written to the ledger not silently zeroed, OQ-09 with counsel |
| **Fee charged without valid consent** *(Release 2)* | Medium | High (chargebacks, disputes) | Policy consent captured and timestamped before the card is saved; no-shows confirmed by a human before charging |
| **Unpaid no-show fees never collected** *(Release 1)* | High | Medium (revenue leak, policy loses its deterrent) | Fee surfaced to the Manager at the client's next booking; a standing report of outstanding fees; resolved permanently in Release 2 |
| **Stripe webhook missed during an outage** *(Release 2)* | Medium | High (unrecorded payment or membership charge) | Idempotent handler keyed on event id; Stripe retries 3 days; restore runbook includes checking failed deliveries |
| Earnings wrong after a rate change | Medium | High (contractor trust) | Effective-dated six-rung ladder + rate snapshot on every earning line + locked periods |
| **Therapist roster enumerated through the client app** *(Release 2)* | Medium | Medium (staff privacy, poaching) | No roster endpoint, 2-character minimum, capped results, rate limits, separate bundle |
| Sensitive client information exposed | Low | Severe | Column encryption on preferences and care notes, scoped access, read-access audit logging |
| Duplicate client records from phone bookings | Very high | Medium (broken history and retention reporting) | Phone-normalised search + a merge tool in Phase 1, not later |
| Single server outage during business hours | Medium | Severe (four locations cannot book) | Daily printed schedule, rehearsed 2-hour restore runbook, VM snapshots |
| AngularJS end-of-life | Certain | Medium | All logic in Rails, thin components, isolated API services — migration is a view-layer swap |
| DST bugs in the 4-hour window and fee jobs | Medium | Medium | Instant arithmetic, never wall-clock; explicit DST tests |
| **Contractor classification** | — | High (legal) | Out of the software's hands; flagged as RISK-04 in doc 01 §8 |
| Scope creep into in-salon card processing | Medium | High (PCI scope, timeline) | ADR-10 holds the line: gateway for online only, and not before Release 2 |
| **Release 2 never happens and the deferred rules are forgotten** | Medium | Medium (FRS §5.1, §21 and §23 silently unimplemented) | The gap is stated in §1, annotated on every affected rule, and the schema already carries the columns — see doc 02 §3.7 |

---

## 5. Definition of Done for the Architecture

Before implementation begins, all of the following should be true:

- [ ] **OQ-01** (add-on pay) and **OQ-02** (staff walk-ins) answered
- [ ] Assumptions A-01 … A-19 reviewed and confirmed or corrected
- [ ] The business rules index (doc 01 §7) reviewed by the Owner in plain language
- [ ] **RISK-01 / OQ-09** (gift card expiry) raised with counsel
- [ ] **OQ-10** answered — does the platform pay therapists, or only report what is owed?
- [ ] The full service menu for all four locations (FRS §19) supplied as structured data for seeding
- [ ] Room inventory (FRS §20) confirmed against the physical rooms, including which services each
      room type may host
- [ ] Existing client list and any outstanding gift cards identified for migration (FRS §24)
- [ ] Expected volume confirmed for sizing (OQ-14)
- [ ] **OQ-11** answered — what a Manager sees when a client with an unpaid fee books again
- [ ] Agreed that Release 1 ships with no payment gateway, so deposits are not taken and no-show
      fees are collected by hand at the next visit
- [ ] Agreement that the eighteen Release 1 scheduling tests (doc 03 §6.1) gate Phase 1 completion

Deferred to Release 2, and not blocking Release 1:

- [ ] Stripe account created and the cancellation-policy wording agreed for the booking flow
- [ ] Decision on whether Phase 5 (client booking) may ship before Phase 6 (online payment)
