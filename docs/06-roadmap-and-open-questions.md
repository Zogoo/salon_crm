# Delivery Roadmap, Assumptions & Open Questions

**Version:** 1.0 · Read §3 before any implementation begins.

---

## 1. Phased Delivery

The sequencing principle: **build the resource-scheduling core first and correctly**, because
everything else (payroll, revenue, utilisation, retention) is derived from appointment and shift
data. A wrong scheduling model is the only mistake here that cannot be patched later.

### Phase 0 — Foundations (1–2 weeks)

- Rails app, Postgres 16 with `btree_gist` / `pg_trgm` / `citext`, Vite Ruby + AngularJS shells
- Users, roles, sessions, TOTP, Pundit skeleton with `verify_authorized` enforced
- Locations, business hours, closures, rooms
- Audit log infrastructure
- CI pipeline, staging deploy, backup + restore drill

**Exit criteria:** a manager can log in, see their locations, and the restore runbook has been
executed successfully once.

### Phase 1 — Scheduling core (3–4 weeks) — *the critical phase*

- Service catalogue: services, variants, durations, buffers, location prices (effective-dated)
- Staff profiles, locations, qualifications, effective-dated rates
- Availability requests, recurring patterns, time-off, shift approval and publishing
- **Availability search engine** (doc 03)
- **Appointments with both exclusion constraints** (doc 03 §4)
- Day-board calendar UI: rooms × time grid, drag to reschedule
- Appointment lifecycle transitions
- Customer records, search, merge

**Exit criteria:** all ten scheduling tests in doc 03 §6.1 pass, including the concurrency test.
Do not proceed until the concurrent-booking test is green.

### Phase 2 — Money and operations (2–3 weeks)

- Orders, line items, discounts
- Payments: cash, card, Zelle, online — split payments, void
- Gift cards: all three types, ledger, redemption, reconciliation job
- Receipts
- Email confirmations and reminders; cancellation window; no-show tracking
- Customer intake forms + consent (encrypted)
- SOAP notes (encrypted, append-only)

**Exit criteria:** a full day can be operated end to end — book, check in, serve, note, pay, close.
Gift card ledger reconciles to zero drift.

### Phase 3 — Payroll and reporting (2–3 weeks)

- Pay periods, timesheet generation from published shifts, adjustments, locking
- Pay statements with PDF export
- Revenue report (with gift card liability separated)
- Utilisation report
- Salary summary
- Customer retention report
- XLSX/PDF export pipeline

**Exit criteria:** one historical month closes correctly and the salary total reconciles by hand
against the shift schedule.

### Phase 4 — Customer-facing (2–3 weeks)

- Public booking page: service → location → date → slot → confirm
- Slot holds
- Signed-token booking management (view, cancel)
- Self-service intake form link
- Public gift card balance lookup
- Rate limiting, bot protection

### Phase 5 — Growth features (backlog, not committed)

- Packages and memberships
- SMS notifications
- Waitlist for fully booked slots
- Customer accounts with login
- Marketing campaigns (birthday, lapsed-customer win-back)
- Accounting export
- Card payment processing (would introduce PCI scope — a separate decision)

**Total to a fully operational system: roughly 10–15 weeks of focused work**, excluding design and
UAT.

---

## 2. Assumptions Made

These were not stated, and I have chosen a default. Each is cheap to change **now** and expensive
to change after Phase 1. Please confirm or correct.

| # | Assumption | Impact if wrong |
|---|---|---|
| A-01 | Single currency, **USD** | Low — mechanical migration |
| A-02 | Single language, **English** UI | Medium — i18n is much cheaper to add up front than to retrofit |
| A-03 | All locations in the **United States**; possibly multiple timezones, handled per-location | Low — already modelled |
| A-04 | **Sales tax is out of scope** in v1 (massage services are untaxed in many US states; gift cards are not taxed at sale). A `tax_cents` column exists but is always 0. | Medium — if tax applies, rules are per-state and per-product-type |
| A-05 | **Tips are not tracked** per staff (you selected hourly-only pay). A `tip_cents` column exists on orders but is not allocated to staff. | Medium — if tips must be distributed and reported, that is a real feature |
| A-06 | **Slot granularity 15 minutes**, per-location configurable | Low |
| A-07 | **Room turnover buffer 15 minutes**, per-variant configurable | Low |
| A-08 | **Cancellation window 24 hours**, per-location configurable | Low |
| A-09 | **Pay period is calendar-monthly** | Medium — biweekly is common in the US and changes the payroll model slightly |
| A-10 | **Breaks are unpaid** and deducted from shift hours via `break_minutes` | Medium — affects every salary figure |
| A-11 | Staff qualification is at **service** level, not per-duration | Low |
| A-12 | **No customer login accounts** in v1; booking management via signed email link | Low — additive later |
| A-13 | **No deposits or prepayment** for online bookings (follows from record-only payments) | Medium — no-show risk on online bookings is unmitigated |
| A-14 | The **"online" payment method** means an externally-received transfer (PayPal/Venmo/bank) recorded manually — not a gateway | **High if wrong** — see OQ-01 |
| A-15 | Gift cards are sold **in salon only**, not online | Medium — see OQ-02 |
| A-16 | Data retention **7 years**, soft delete only | Low |
| A-17 | Existing customer/appointment data will need **migration from spreadsheets or an existing system** | Medium — needs a scoped import task |

---

## 3. Open Questions — Please Answer Before Implementation

Ordered by architectural blast radius. **OQ-01 through OQ-05 should be answered before Phase 1
starts**; the rest can be resolved during their phase.

### Blocking (answer now)

**OQ-01 — What does the "online" payment method actually mean?**
You confirmed payments are *recorded, not processed*, yet online self-service booking is in scope.
So: does an online customer (a) pay nothing and settle in the salon, (b) send money via
Zelle/PayPal out-of-band which the front desk records afterwards, or (c) do you eventually want a
card gateway? Option (c) is a materially different system — PCI scope, refund flows, webhook
reconciliation. I have assumed (a) + (b).

**OQ-02 — Can gift cards be bought online?**
If yes, this is the one place where money genuinely must be collected before delivery, which forces
a payment gateway even though everything else is record-only. If no, gift cards stay a front-desk
product and v1 needs no gateway at all.

**OQ-03 — Are tips taken, and must they be tracked per therapist?**
Very common in US massage salons, frequently a legal reporting obligation, and it interacts with
payment method (a cash tip vs a tip on a card). You selected hourly-only pay, which suggests tips
may go directly to staff and never touch the system — please confirm.

**OQ-04 — Is there a no-show or late-cancellation fee?**
You have no-show tracking in scope. Tracking is cheap; *charging* is not — with no stored payment
method, a fee can only be recorded as a debt against the customer and collected at their next
visit. Do you want that, or is tracking alone sufficient?

**OQ-05 — What is the pay period, and are breaks paid?**
Monthly or biweekly? Are breaks within a shift paid or unpaid? These two answers change every
number the payroll module produces.

### Important (answer before their phase)

**OQ-06 — Overtime rules.** Is there an overtime multiplier past 40 hours/week or 8 hours/day? US
state law varies (California is daily; most states are weekly). If yes, timesheet lines need an
overtime classification.

**OQ-07 — Couples or back-to-back bookings.** You chose 1 room + 1 therapist per appointment. But
does a customer ever book two services in sequence (e.g. 60-min massage then 30-min scalp), and
should the system chain those as one visit? This is far cheaper to design in now than to add later.

**OQ-08 — Can a manager be a therapist?** In small salons, managers frequently also give massages.
Currently roles are exclusive. If one person needs both, the role model needs a small change (a
staff profile attachable to a manager account).

**OQ-09 — Does a therapist need to see customer health intake before the appointment?** Affects
whether intake data is pushed into the therapist's schedule view or fetched on demand, and how much
audit-logging volume you generate.

**OQ-10 — Sales tax.** Do any of your states tax massage services or gift card sales? If yes, I need
the rules per location.

**OQ-11 — Gift card expiry.** US federal law (CARD Act) generally prohibits expiry within 5 years
of issue, and several states prohibit expiry outright. Do you want expiry at all, and do you know
your states' rules? I would default to **no expiry** unless you confirm otherwise — it is the safe
position.

**OQ-12 — Data migration.** Is there existing customer, appointment, or gift card data to import?
From what — spreadsheets, another booking system, paper? Outstanding gift cards in particular must
be loaded with correct balances or you have unrecorded liability.

### Nice to resolve

**OQ-13 — Who owns the customer relationship across locations?** Is a customer shared company-wide
(book at any branch, one history) or per-location? I have assumed **company-wide**, which is the
better business model and matches "track customer histories".

**OQ-14 — Waitlist.** When a desirable slot is full, do you want to capture the demand? This is one
of the highest-ROI features in salon software and worth confirming as a phase-5 item.

**OQ-15 — Reminder timing and channel.** 24 hours before is the default. Do you want a second
reminder (e.g. 2 hours)? Email only confirmed — is SMS genuinely out, given the higher no-show
reduction it delivers?

**OQ-16 — Branding, and is there an existing website** the booking page must match or embed into?

**OQ-17 — Expected volume.** Roughly how many appointments per location per day, and how many staff
in total? This validates the single-server sizing.

---

## 4. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-booking under concurrent phone + online booking | High without care | Severe (customer turned away, staff conflict) | Postgres exclusion constraints (doc 03 §4) — designed out, not tested out |
| Single server outage during business hours | Medium | Severe (cannot book) | Daily printed schedule fallback, rehearsed 2-hour restore runbook, VM snapshots |
| Gift card liability misreported as revenue | High (very common) | Severe (overstated profit, tax exposure) | BR-19 enforced in the reporting layer; liability report shipped in Phase 3 |
| Payroll wrong after a rate change | Medium | High (staff trust, legal) | Effective-dated rates + rate snapshot on each timesheet line + locked periods |
| Health data exposure | Low | Severe (legal, reputational) | Column encryption, front-desk exclusion, read-access audit logging |
| Duplicate customer records from phone bookings | Very high | Medium (broken history and retention reporting) | Phone-normalised search + a merge tool shipped in Phase 1, not later |
| AngularJS end-of-life | Certain | Medium (long-term maintainability) | All logic in Rails, thin components, isolated API services — migration is a view-layer swap |
| Scope creep into payment processing | Medium | High (PCI scope, timeline) | Answer OQ-01 and OQ-02 now and hold the line |
| DST bugs in recurring shifts | Medium | Medium (wrong schedules twice a year) | Explicit DST tests, local-time materialisation |

---

## 5. Definition of Done for the Architecture

Before implementation begins, all of the following should be true:

- [ ] OQ-01 … OQ-05 answered
- [ ] Assumptions A-01 … A-17 reviewed and confirmed or corrected
- [ ] The business rules index (doc 01 §7) reviewed by the salon owner/manager in plain language
- [ ] Existing data sources identified for migration (OQ-12)
- [ ] Expected volume confirmed for sizing (OQ-17)
- [ ] Agreement that the ten scheduling tests (doc 03 §6.1) gate Phase 1 completion
