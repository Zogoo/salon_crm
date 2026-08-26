# Delivery Roadmap, Assumptions & Open Questions

**Version:** 1.0 · Read §3 before any implementation begins.
**Aligned to:** FRS v7

> FRS v7 §26 states that all open items are resolved. That is true of the **business** questions —
> membership price, rollover cap, notifications and authentication are all settled. What follows
> are the **implementation** questions v7 does not reach, plus two places where v7 contradicts
> itself.

---

## 1. Phased Delivery

The sequencing principle: **build the resource-scheduling core first and correctly**, because
everything else — earnings, revenue, ratings, membership redemption — is derived from appointment
data. A wrong scheduling model is the only mistake here that cannot be patched later.

### Phase 0 — Foundations (1–2 weeks)

- Rails app, Postgres 16 with `btree_gist` / `pg_trgm` / `citext`, Vite Ruby + three AngularJS
  shells (console, client, kiosk)
- Users and the four roles; staff sessions; TOTP for Owner; client SMS-code auth
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
- Appointment lifecycle transitions
- Client records, phone search, "Add New Client", merge tool

**Exit criteria:** all twenty scheduling tests in doc 03 §6.1 pass. Tests 1, 11, 12 and 16 —
concurrency, couples cardinality, atomic two-therapist rollback, and the 15-minute gap — gate the
phase. Do not proceed until they are green.

### Phase 2 — Money and operations (3–4 weeks)

- Orders, line items, discounts, the `revenue_category` classification
- Payments: recorded methods (card terminal, cash, Zelle, other) and split payment
- **Stripe**: deposits and full prepayment, saved cards with policy consent, off-session fee
  charges, refunds, webhook handling
- Cancellation and no-show policy: the 4-hour window, 20% fees, full refunds
- Tips, including the two-therapist split
- Gift cards: physical and digital, ledger, barcode lookup, cross-location redemption,
  reconciliation job
- Client preferences form (versioned) and care notes (append-only, encrypted)
- Email + SMS notifications: confirmation, reminder, fee notice, approval decisions

**Exit criteria:** a full day can be operated end to end at one location — book, confirm, check in,
serve, note, pay with a split across two methods, close. The gift card ledger reconciles to zero
drift. A no-show fee charges correctly against a saved card in Stripe test mode, and a ≥4-hour
cancellation refunds in full.

### Phase 3 — Earnings and reporting (2–3 weeks)

- `earning_lines` generated on appointment completion, with rate snapshotting
- Manual session and tip entry (Owner)
- Semi-monthly period generation, statements, adjustments, locking
- Owner dashboard (FRS §15)
- Daily revenue report (FRS §10), client log (FRS §9), staff earnings report (FRS §4, §8)
- Gift card liability report
- XLSX / PDF export pipeline

**Exit criteria:** one historical half-month closes correctly and a therapist's total reconciles by
hand against their completed appointments. Revenue, liabilities and fees appear as three separate
figures and never as one.

### Phase 4 — Client-facing (3–4 weeks)

- Client accounts: registration, SMS-code login, profile
- Public booking: service → location → date → slot → therapist search → deposit → confirm
- Slot holds across the payment step
- My bookings, self-service cancellation with the fee rule applied
- Digital gift card purchase
- Rating: SMS link and the in-location kiosk
- Rate limiting, bot protection, and the roster-privacy guarantees (BR-13)

**Exit criteria:** a client can register, book, pay a 20% deposit, receive email **and** SMS
confirmation, cancel outside the window for a full refund, and rate a completed session. A
penetration attempt cannot enumerate the therapist roster through any public endpoint.

### Phase 5 — Membership (2 weeks)

- Enrolment, Stripe subscription at $80/month
- Monthly credit grant with the 3-credit cap
- Redemption against the included 60-minute massage
- Upgrade pricing (the difference)
- The 15-day cancellation notice rule
- Membership report

**Exit criteria:** a member accrues credits to the cap, redeems one against a booking at $0,
redeems one against a lymphatic massage paying only the difference, and a cancellation requested
14 days before renewal takes effect after the *following* period.

### Phase 6 — Data migration and go-live (1–2 weeks)

- Import the existing client list: contact information and appointment history (FRS §24)
- **Import any outstanding gift cards with correct balances** — unrecorded liability is the
  expensive failure mode here
- Parallel-run one location for a week before switching the rest
- Train the four Managers; print the fallback day sheets

**Total: roughly 15–20 weeks of focused work**, excluding UI design and UAT. The four heaviest
items in that total are the multi-therapist scheduling core, Stripe, client accounts and
membership — none of which can be deferred without breaking a rule in FRS v7.

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
| **A-07** | The **deposit and fee base** is the appointment total (services + add-ons + enhancements), **excluding tip**. | Low |
| **A-08** | **The buffer trails the appointment** rather than surrounding it, producing exactly one 15-minute gap between consecutive bookings. | Low — but see doc 03 §1.1 |
| **A-09** | A **three-table room** at Skokie is bookable by any service needing 1–3 tables; nothing in FRS v7 describes a three-person service, so it currently serves as an overflow single/couple room. | Low — see OQ-06 |
| **A-10** | **Single head spa runs in a head-spa room** (Luma has 2, both described as "head-spa couple rooms"). | Low |
| **A-11** | **Client accounts are company-wide**, as are client profiles, gift cards and memberships. | Low |
| **A-12** | **Walk-ins are entered by Owner or Manager**, not Staff — following FRS §2 over FRS §3/§21. | Medium — see OQ-02 |
| **A-13** | **A membership credit may be redeemed at any of the four locations.** | Low |
| **A-14** | **Reminder timing is 24 hours before start.** FRS §22 requires a reminder but gives no timing. | Low — see OQ-05 |
| **A-15** | Data retention **7 years**, soft delete only. | Low |
| **A-16** | **English UI in v1**, with all strings in i18n files so Mongolian or Spanish is additive. | Low |
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

**OQ-03 — How is a membership upgrade priced?**
FRS §23 says a member "can pay extra" for a different service. Is the extra (a) the difference
between the two list prices at that location (A-04), (b) the difference from the $80 membership
price, or (c) a fixed upgrade fee? Also: does an upgrade consume the monthly credit, or is it
charged in full and the credit preserved?

**OQ-04 — What happens to a therapist request nobody approves?**
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

**OQ-09 — Gift card expiry.** See RISK-01 in doc 01 §8. FRS §12 sets 12 months. The federal CARD
Act sets a five-year floor for the funds behind most gift certificates, and Illinois has its own
provisions. The system implements expiry as a configurable value so the policy is yours to set —
but please confirm the 12-month figure with counsel before it is switched on, because the exposure
is a claim from a cardholder, not a bug.

**OQ-10 — Who receives the money?** Therapists are 1099 contractors earning per session. Does the
platform need to **pay them** (Stripe Connect, ACH, a payout file), or does it only need to
**report** what is owed so payment happens outside the system? These documents assume reporting
only. Actual payouts are a substantially larger piece of work.

### Nice to resolve

**OQ-11 — Rating follow-up.** Ratings are collected but FRS v7 does not say what happens to a low
one. Should a score below some threshold alert the Owner or the location Manager?

**OQ-12 — Can a client rebook the same therapist directly?**
The roster is deliberately unbrowsable, but a returning client already knows who they saw. Should
"book again with Anna" appear on their own visit history? It leaks no one else's identity and is
the single highest-value convenience in the client app.

**OQ-13 — Expected volume.** Roughly how many appointments per location per day? This validates the
single-server sizing and the availability-search budget. The estimates in doc 03 §2.2 assume ~20
per location per day.

**OQ-14 — Branding and existing website.** Is there a site the booking flow must match or embed
into?

**OQ-15 — Does anything need to be bilingual at launch** — the client booking flow, the rating
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
| **Fee charged without valid consent** | Medium | High (chargebacks, disputes) | Policy consent captured and timestamped before the card is saved; no-shows confirmed by a human before charging |
| **Stripe webhook missed during an outage** | Medium | High (unrecorded payment or membership charge) | Idempotent handler keyed on event id; Stripe retries 3 days; restore runbook includes checking failed deliveries |
| Earnings wrong after a rate change | Medium | High (contractor trust) | Effective-dated six-rung ladder + rate snapshot on every earning line + locked periods |
| **Therapist roster enumerated through the client app** | Medium | Medium (staff privacy, poaching) | No roster endpoint, 2-character minimum, capped results, rate limits, separate bundle |
| Sensitive client information exposed | Low | Severe | Column encryption on preferences and care notes, scoped access, read-access audit logging |
| Duplicate client records from phone bookings | Very high | Medium (broken history and retention reporting) | Phone-normalised search + a merge tool in Phase 1, not later |
| Single server outage during business hours | Medium | Severe (four locations cannot book) | Daily printed schedule, rehearsed 2-hour restore runbook, VM snapshots |
| AngularJS end-of-life | Certain | Medium | All logic in Rails, thin components, isolated API services — migration is a view-layer swap |
| DST bugs in the 4-hour window and fee jobs | Medium | Medium | Instant arithmetic, never wall-clock; explicit DST tests |
| **Contractor classification** | — | High (legal) | Out of the software's hands; flagged as RISK-04 in doc 01 §8 |
| Scope creep into in-salon card processing | Medium | High (PCI scope, timeline) | ADR-10 holds the line: gateway for online only |

---

## 5. Definition of Done for the Architecture

Before implementation begins, all of the following should be true:

- [ ] **OQ-01** (add-on pay) and **OQ-02** (staff walk-ins) answered
- [ ] Assumptions A-01 … A-17 reviewed and confirmed or corrected
- [ ] The business rules index (doc 01 §7) reviewed by the Owner in plain language
- [ ] **RISK-01 / OQ-09** (gift card expiry) raised with counsel
- [ ] **OQ-10** answered — does the platform pay therapists, or only report what is owed?
- [ ] The full service menu for all four locations (FRS §19) supplied as structured data for seeding
- [ ] Room inventory (FRS §20) confirmed against the physical rooms, including which services each
      room type may host
- [ ] Existing client list and any outstanding gift cards identified for migration (FRS §24)
- [ ] Expected volume confirmed for sizing (OQ-13)
- [ ] Stripe account created and the cancellation-policy wording agreed for the booking flow
- [ ] Agreement that the twenty scheduling tests (doc 03 §6.1) gate Phase 1 completion
