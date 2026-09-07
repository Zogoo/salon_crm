# Delivery Roadmap

**Version:** 1.1 · **Aligned to:** FRS v7
**Companion:** [`07-open-questions-and-risks.md`](07-open-questions-and-risks.md) — the limitations
and risks behind this plan, plus the pre-implementation checklist.

---

## 1. Delivery Posture: Internal First

This platform is, at this stage, **an internal management tool**. Everything in Release 1 is
operated by an Owner, a Manager or a Therapist standing in one of the four locations. Nothing in it
requires a client to log in, open a browser, or enter a card.

That decision defers three things that FRS v7 describes and that this design fully specifies:
client self-service booking (§5.1), online payment collection — deposits, prepayment and automatic
no-show fees (§5.1, §21) — and online gift card purchase (§12). They remain designed, modelled and
documented throughout this design package; they are simply not built first.

**What deferring them costs, stated plainly.** Three business rules degrade in Release 1:

| Rule | Release 1 behaviour | Release 2 behaviour |
|---|---|---|
| Deposits at booking (FRS §5.1) | Not taken — bookings are internal and paid at checkout | 20% or full payment via Stripe |
| No-show / late-cancel fee (BR-19) | **Calculated and recorded as owed**, not charged. The 4-hour window still runs; the fee becomes an open `Fee` order line **visible on the client profile only** — the front desk is not warned at the next booking | Charged automatically against the saved card |
| Membership billing (BR-38) | Enrolment, credits, rollover cap and the 15-day notice all work; the **$80 monthly payment is recorded by hand** like any other payment | Stripe subscription bills automatically |

Everything else — the scheduling core, earnings, gift cards, reporting — is complete in Release 1.

The sequencing principle within each release: **build the resource-scheduling core first and
correctly**, because everything else (earnings, revenue, ratings, membership redemption) is derived
from appointment data. A wrong scheduling model is the only mistake here that cannot be patched
later.

---

## 2. Release 1 — Internal Management Platform

### Phase 0 — Foundations (1–2 weeks)

- Rails app, Postgres 16 with `btree_gist` / `pg_trgm` / `citext`, Vite Ruby + the **console and
  kiosk** AngularJS shells (the client bundle is Release 2)
- Users and the three staff roles; staff sessions; TOTP for Owner
- Pundit skeleton with `verify_authorized` enforced from the first controller
- **Seed the four locations, their business hours, and all 29 typed rooms** (FRS §20)
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

**Exit criteria:** the twenty-two Release 1 scheduling tests in doc 03 §6.1 pass. Tests 1, 11, 12
and 18 — concurrency, couples cardinality, atomic two-therapist rollback, and the 15-minute gap —
gate the phase. Do not proceed until they are green.

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

## 3. Release 2 — Client-Facing (designed, not scheduled)

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
