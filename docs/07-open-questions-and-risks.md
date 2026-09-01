# Assumptions, Open Questions & Risks

**Version:** 1.1 · **Aligned to:** FRS v7
**Companion:** [`06-delivery-roadmap.md`](06-delivery-roadmap.md) — the phased plan these items
qualify.

> **Status:** every question raised against FRS v7 has been answered and folded into the design as
> rules across this design package. §2.1 holds the three small items still open, none of which blocks
> Release 1; §2.2 states the limitations the settled decisions accept.

---

## 1. Assumptions

Defaults chosen where FRS v7 and the Owner's decisions are both silent. Each is cheap to change
now and expensive to change after its phase. Anything the Owner has since settled is no longer an
assumption and lives in the design as a rule.

| # | Assumption | Impact if wrong |
|---|---|---|
| **A-01** | **Tips go 100% to the performing therapist**, split evenly between two therapists on a couples or four-hands appointment unless overridden. | Medium |
| **A-02** | **Sales tax is out of scope.** Illinois generally does not tax massage services, and gift cards are not taxed at sale. A `tax_cents` column exists and is always 0. | Medium — per-state rules if wrong |
| **A-03** | The **deposit and fee base** is the appointment total (services + add-ons + enhancements), **excluding tip**. Release 1 calculates the fee and records it on the client profile only — no booking-time warning; Release 2 charges it. | Low |
| **A-04** | **The buffer trails the appointment** rather than surrounding it, producing exactly one 15-minute gap between consecutive bookings. | Low — but see doc 03 §1.1 |
| **A-05** | **Single head spa runs in a head-spa room** (Luma has 2, both described as "head-spa couple rooms"). | Low |
| **A-06** | **Client accounts are company-wide**, as are client profiles, gift cards and memberships. | Low |
| **A-07** | Data retention **7 years**, soft delete only. | Low |
| **A-08** | **A therapist works at one location at a time**; the location-change request moves them, it does not add a second location. | Medium — many-to-many would change the shift and availability model |
| **A-09** | **Membership is billed by hand in Release 1** — the Manager records the $80 like any other payment, and the credit grant is triggered by that recorded payment rather than by a Stripe webhook. | Medium — operationally manual until Release 2 Phase 7 |
| **A-10** | **Notifications ship in Release 1.** Confirmations, reminders, fee notices, low-rating alerts and rating links need no client account — only a phone number and an email address. | Low — but see the SMS cost note in doc 04 §10 |
| **A-11** | **The low-rating alert threshold is 6 or below** on the 1–10 scale, configurable per location. The alert is required (BR-45a) but no number was set. | Low — one config value |
| **A-12** | **A `Fee` order line is the only representation of an unpaid no-show fee.** No separate debt table, no booking-time interruption. | Low |

---

## 2. Open Questions & Accepted Limitations

### 2.1 Open questions

Three items remain unsettled. None blocks Release 1.

**OQ-01 — What is the low-rating alert threshold?** A low rating alerts the Owner and that
location's Manager (BR-45a), but "low" has no agreed number. Defaulted to **6 or below** on the
1–10 scale (A-11), configurable per location. Worth ten seconds of the Owner's attention: set too
high it becomes noise and gets ignored, set too low it never fires.

**OQ-02 — Does the 45-minute auto-approval need a same-day floor?** BR-15a auto-approves a pending
therapist request after 45 minutes. For a request made a week out that is clearly right. For one
made *during* those 45 minutes — a client booking for 90 minutes' time — the appointment may start
before the timer elapses. Suggested rule: auto-approve at 45 minutes **or** 2 hours before start,
whichever comes first, so a same-day request is never left hanging past the point of usefulness.

**OQ-03 — What is the website URL?** The reference supplied,
`www.mongolianmassagelab@gmail.com`, is an email address with a `www.` prefix and will not resolve.
Needed only for Release 2 branding, so it blocks nothing now — but if a live site exists that the
client booking flow should match or embed into, the real domain is needed before Phase 5.

### 2.2 Accepted limitations

Not questions — settled decisions whose consequences are worth stating once, plainly.

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

## 3. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-booking under concurrent front-desk and online booking | High without care | Severe | Postgres exclusion constraints on `appointments` **and** `appointment_staff` (doc 03 §4) — designed out, not tested out |
| **Half-created two-therapist appointment** | Medium | Severe (couples booking with one therapist) | Both `appointment_staff` rows inside one transaction; test 12 gates Phase 1 |
| **`appointment_staff` drifting from its parent** | Low | Severe (silent double-booking) | Trigger + nightly `VerifyAppointmentStaffSyncJob` |
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
| AngularJS end-of-life | Certain | Medium | All logic in Rails, thin components, isolated API services — migration is a view-layer swap |
| DST bugs in the 4-hour window and fee jobs | Medium | Medium | Instant arithmetic, never wall-clock; explicit DST tests |
| **Contractor classification** | — | High (legal) | Out of the software's hands; flagged as RISK-04 in doc 01 §8 |
| **Shared Manager logins destroy per-person attribution** | Certain | Medium (no accountability for payments, voids, approvals) | Accepted; cannot be fixed retroactively — see §2.2. Adding per-person Manager accounts before go-live is the only cheap moment |
| **SMS spend at peak volume** | Medium | Low–Medium (~$350–400/month at 400 appts/day) | Two reminders plus confirmation and rating request is 4 SMS per appointment. Both levers — dropping the 2 h reminder to email, or limiting rating requests — are configuration. See doc 04 §10 |
| **Combined-session pay disputes** | Medium | Medium (contractor trust) | BR-33 pays a 60+30 as one 90-minute session, normally *less* than two separate lines. `earning_lines.covers_item_ids` makes every combined line explainable on the statement; explain the rule at onboarding rather than in arrears |
| Scope creep into in-salon card processing | Medium | High (PCI scope, timeline) | ADR-10 holds the line: gateway for online only, and not before Release 2 |
| **Release 2 never happens and the deferred rules are forgotten** | Medium | Medium (FRS §5.1, §21 and §23 silently unimplemented) | The gap is stated in §1, annotated on every affected rule, and the schema already carries the columns — see doc 02 §3.7 |

---

## 4. Definition of Done for the Architecture

Before implementation begins, all of the following should be true:

- [ ] Assumptions A-01 … A-12 reviewed and confirmed or corrected
- [ ] **OQ-01** — confirm the low-rating alert threshold (default: 6 or below)
- [ ] **OQ-02** — confirm the same-day floor on 45-minute auto-approval
- [ ] The business rules index (doc 01 §7) reviewed by the Owner in plain language
- [ ] Gift card wording checked with counsel — a card described as "expired" must not imply the
      balance is gone, because it is not (BR-30)
- [ ] The full service menu for all four locations (FRS §19) supplied as structured data for seeding
- [ ] Room inventory (FRS §20) confirmed against the physical rooms, including which services each
      room type may host
- [ ] Existing client list and any outstanding gift cards identified for migration (FRS §24)
- [ ] Decide **before go-live** whether Managers get individual logins (§2.2) — the one decision
      that cannot be applied retroactively
- [ ] Agreed that Release 1 ships with no payment gateway, so deposits are not taken and no-show
      fees are collected by hand at the next visit
- [ ] Agreement that the twenty-two Release 1 scheduling tests (doc 03 §6.1) gate Phase 1 completion

Deferred to Release 2, and not blocking Release 1:

- [ ] Stripe account created and the cancellation-policy wording agreed for the booking flow
- [ ] Decision on whether Phase 5 (client booking) may ship before Phase 6 (online payment)
- [ ] **OQ-03** — the real website URL, for branding the client booking flow
