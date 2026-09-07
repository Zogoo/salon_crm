# Limitations & Risks

**Version:** 2.0 · **Aligned to:** FRS v7 and the implemented stack (doc 08)
**Companion:** [`06-delivery-roadmap.md`](06-delivery-roadmap.md) — the phased plan these items
qualify.

> **Status:** nothing is outstanding. Every question raised against FRS v7 has been answered, and
> every assumption this document used to carry has been confirmed by the Owner and promoted into
> the design as a numbered business rule (doc 01 §7). What remains here is the consequences of
> those decisions: §1 the limitations they accept, §2 the risk register, §3 what must be true
> before implementation begins.

---

## 1. Accepted Limitations

Settled decisions whose consequences are worth stating once, plainly, so nobody rediscovers them
the hard way.

**Shared Manager logins weaken the audit trail.** One login per location, used by whoever is on the
desk, means `audit_logs` can attribute an action to *Skokie's front desk* but never to a person.
Every payment, void, approval and gift card sale inherits that limitation. It is cheap to change —
adding Manager accounts is trivial — but attribution **cannot be reconstructed retroactively** for
anything recorded before the change. If individual accountability ever matters, the moment to add
accounts is before go-live, not after.

**Gift card liability never ages off the books.** Because expiry forfeits nothing (BR-30), old
small balances accumulate on the liability report indefinitely. That is the correct accounting
treatment and it is what was asked for; the ageing buckets in `/reports/gift_card_liability` exist
so those balances stay visible rather than quietly growing.

**Unpaid no-show fees will mostly go uncollected in Release 1.** Profile-only (BR-19) means nobody
is prompted at the moment collection is possible. The weekly `OutstandingFeesReportJob` digest is
the only backstop. This is a deliberate trade of revenue for front-desk friction, and it resolves
itself in Release 2 when fees charge automatically.

**Combining a base session with its add-on usually pays the therapist less.** BR-33 pays a 60+30 as
one 90-minute session, and a 90 rate is normally below a 60 plus a 30. This is the intended
reading — one continuous 90-minute session is one 90-minute session — but it is the kind of thing
that surfaces at the first payout. `earning_lines.covers_item_ids` makes every combined line
explainable on the statement; explain the rule at onboarding rather than in arrears.

---

## 2. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-booking under concurrent booking | High without care | Severe | **No longer designed out — see ADR-17 / doc 08 §2.** SQLite has no exclusion constraints, so prevention is a conflict check inside `BEGIN IMMEDIATE`, concentrated in `Scheduling::BookAppointment` as the sole writer. The threaded concurrency spec *is* the guarantee; it must never be deleted or skipped |
| **Half-created two-therapist appointment** | Medium | Severe (couples booking with one therapist) | Both `appointment_staff` rows inside one transaction; test 12 gates Phase 1 |
| **`appointment_staff` drifting from its parent** | **Medium** | Severe (silent double-booking) | Raised from Low: the Postgres design kept the denormalised interval and status in step with a database trigger, but SQLite has none, so `BookAppointment` and `TransitionStatus` maintain them in application code. `VerifyAppointmentStaffSyncJob` is specified in doc 04 §8 and **not yet built** — until it is, drift would be silent |
| Gift card liability misreported as revenue | High (very common) | Severe (overstated profit, tax exposure) | `revenue_category` on every line item; liability report in Phase 3 |
| **Membership credits misreported as revenue** | High | Severe | Same mechanism — membership billing is a liability until the credit is redeemed |
| Gift card expiry wording | Low | Low | An expired card keeps its balance and stays redeemable (BR-30), so nothing is forfeited and the CARD Act and Illinois concerns — which are about forfeited funds — largely fall away. What remains is wording: never tell a customer a card is "expired" in a way implying the money is gone |
| **Fee charged without valid consent** *(Release 2)* | Medium | High (chargebacks, disputes) | Policy consent captured and timestamped before the card is saved; no-shows confirmed by a human before charging |
| **Unpaid no-show fees never collected** *(Release 1)* | **Very high** | Medium (revenue leak, policy loses its deterrent) | The fee is profile-only (BR-19), so nobody is prompted at the one moment collection is possible. The weekly `OutstandingFeesReportJob` digest is the sole mitigation. Disappears in Release 2 |
| **Stripe webhook missed during an outage** *(Release 2)* | Medium | High (unrecorded payment or membership charge) | Idempotent handler keyed on event id; Stripe retries 3 days; restore runbook includes checking failed deliveries |
| Earnings wrong after a rate change | Medium | High (contractor trust) | Effective-dated six-rung ladder + rate snapshot on every earning line + locked periods |
| **Therapist roster enumerated through the client app** *(Release 2)* | Medium | Medium (staff privacy, poaching) | No roster endpoint, 2-character minimum, capped results, rate limits, separate bundle |
| Sensitive client information exposed | Low | Severe | Column encryption on preferences and care notes, scoped access, read-access audit logging |
| Duplicate client records from phone bookings | Very high | Medium (broken history and retention reporting) | Phone-normalised search + a merge tool in Phase 1, not later |
| Single server outage during business hours | Medium | Severe (four locations cannot book) | Daily printed schedule, rehearsed 2-hour restore runbook, VM snapshots |
| Angular major upgrades | Medium | Low | The AngularJS end-of-life risk is gone — the implemented stack is Angular 21 (doc 08 §1). All logic stays in Rails and components are thin, so a future major is a view-layer job, not a rewrite |
| DST bugs in the 4-hour window and fee jobs | Medium | Medium | Instant arithmetic, never wall-clock; explicit DST tests |
| **Contractor classification** | — | High (legal) | Out of the software's hands; flagged as RISK-04 in doc 01 §8 |
| **Shared Manager logins destroy per-person attribution** | Certain | Medium (no accountability for payments, voids, approvals) | Accepted; cannot be fixed retroactively — see §1. Adding per-person Manager accounts before go-live is the only cheap moment |
| **SMS spend at peak volume** | Medium | Low–Medium (~$350–400/month at 400 appts/day) | Two reminders plus confirmation and rating request is 4 SMS per appointment. Both levers — dropping the 2 h reminder to email, or limiting rating requests — are configuration. See doc 04 §10 |
| **Combined-session pay disputes** | Medium | Medium (contractor trust) | BR-33 pays a 60+30 as one 90-minute session, normally *less* than two separate lines. `earning_lines.covers_item_ids` makes every combined line explainable on the statement; explain the rule at onboarding rather than in arrears |
| Scope creep into in-salon card processing | Medium | High (PCI scope, timeline) | ADR-10 holds the line: gateway for online only, and not before Release 2 |
| **Release 2 never happens and the deferred rules are forgotten** | Medium | Medium (FRS §5.1, §21 and §23 silently unimplemented) | The gap is stated in doc 06 §1, annotated on every affected rule, and the schema already carries the columns — see doc 02 §3.7 |
| **Background jobs specified but not built** | Medium | Medium (silent gaps: no fee digest, no drift check, no auto-approval) | Doc 04 §8 lists the job table; the scheduling core shipped without it. `AutoApproveTherapistRequestsJob` (BR-15a), `VerifyAppointmentStaffSyncJob` and `OutstandingFeesReportJob` are all load-bearing for rules that are otherwise only documented |

---

## 3. Definition of Done for the Architecture

Before implementation begins, all of the following should be true:

- [ ] The business rules index (doc 01 §7) reviewed by the Owner in plain language
- [ ] Gift card wording checked with counsel — a card described as "expired" must not imply the
      balance is gone, because it is not (BR-30)
- [ ] The full service menu for all four locations (FRS §19) supplied as structured data for seeding
- [ ] Room inventory (FRS §20) confirmed against the physical rooms, including which services each
      room type may host
- [ ] Existing client list and any outstanding gift cards identified for migration (FRS §24)
- [ ] Decide **before go-live** whether Managers get individual logins (§1) — the one decision
      that cannot be applied retroactively
- [ ] Agreed that Release 1 ships with no payment gateway, so deposits are not taken and no-show
      fees are collected by hand at the next visit
- [ ] Agreement that the twenty-two Release 1 scheduling tests (doc 03 §6.1) gate Phase 1 completion

Deferred to Release 2, and not blocking Release 1:

- [ ] Stripe account created and the cancellation-policy wording agreed for the booking flow
- [ ] Decision on whether Phase 5 (client booking) may ship before Phase 6 (online payment)
