# Build Plan — Scheduling Core

**Version:** 1.0 · **Date:** 2026-09-07 · **Status:** In progress
**Implements:** doc 06 Release 1, Phases 0 and 1
**Stack authority:** the `project-preparator` scaffold at `../project-preparator`

---

## 1. Stack — and where it overrides the design docs

The application is generated from the owner's standard scaffold, which produces **Rails 8 API +
Angular 21 + SQLite**, with Angular compiled into Rails `public/` and served by `SpaController`,
deployed as a single Fly.io app.

Two of the scaffold's choices override what docs 02–05 originally specified. Both were decided by
the owner on 2026-09-07 and are recorded here rather than quietly absorbed.

| Area | Docs originally said | Now | Consequence |
|---|---|---|---|
| Database | PostgreSQL 16 + `btree_gist`, `pg_trgm`, `citext` | **SQLite** | **Material.** See §2 |
| Frontend | AngularJS 1.8.x via Vite Ruby, three bundles | **Angular 21** standalone | Improvement — the docs' own ADR-14 tolerated AngularJS only because it is EOL and all logic sits in Rails |
| Serving | Rails serves the SPA | Unchanged — `SpaController` renders `public/index.html` | None |
| Deployment | Single VM + Postgres | Single Fly.io app + volume | None for this build |

### 1.1 What the frontend change does *not* alter

The three-bundle split in doc 04 §2.3 existed so the client-facing bundle could not physically
contain a therapist roster (BR-13). Release 1 ships **no client-facing bundle at all**, so that
property holds trivially. When Release 2 arrives the same reasoning applies to an Angular 21
project with a second application target.

---

## 2. The database change is a downgrade, and it is the important one

Doc 03 §4 states, in bold, that preventing double-booking "must not rely on application logic",
and ADR-02 rejects application-level locking because it "fails under true concurrency". That
mechanism was Postgres `EXCLUDE USING gist`. **SQLite cannot express it** — no exclusion
constraints, no GiST indexes, no range types.

Five documented invariants lose their database enforcement:

| # | Invariant | Was | Now |
|---|---|---|---|
| 1 | No two active appointments share a room in overlapping time | `EXCLUDE` on `(room_id, during)` | Application check |
| 2 | No therapist in two active appointments at once, any location | `EXCLUDE` on `appointment_staff` | Application check |
| 3 | No two published shifts overlap for one therapist | `EXCLUDE` on `(staff_profile_id, during)` | Application check |
| 4 | Session rate periods never overlap per staff per duration | `EXCLUDE` on `daterange` | Application check |
| 5 | Location price periods never overlap per variant | `EXCLUDE` on `daterange` | Application check |

Two further capabilities are lost: `pg_trgm` trigram indexes (client and therapist name search) and
`citext` (case-insensitive email).

### 2.1 What replaces it

SQLite serialises writers — there is exactly one at a time — so a check-then-insert **is** safe,
but only if both statements sit inside a transaction that already holds the write lock. Rails'
default `BEGIN DEFERRED` acquires that lock lazily, on first write, which leaves precisely the
window the exclusion constraint used to close.

The replacement is therefore three things together, and it is weaker than what it replaces:

1. **`BEGIN IMMEDIATE`** on every booking write — the lock is taken before the conflict check runs,
   not after it passes.
2. **WAL mode + `busy_timeout`**, so readers are never blocked by the writer and a contended writer
   waits rather than failing instantly.
3. **A single service object**, `Scheduling::BookAppointment`, owning every conflict check. No other
   code path may insert an appointment. With the constraint gone, the guarantee has one home
   instead of being enforced by the storage engine everywhere at once.

**Honest statement of the residual risk.** The database will now accept a double-booking if any
future code path writes an appointment without going through that service. Under Postgres it would
have been rejected no matter who wrote it. The concurrency test (§6, test 1) is what stands in for
the constraint, and it must never be deleted or skipped.

Name search degrades to `LIKE` with a lowercase index — adequate at the documented scale (a few
thousand clients per location) and revisitable if it is not.

---

## 3. Scope of this build

**In:** doc 06 Phase 0 and Phase 1 — the scheduling core, end to end.

| Area | What ships |
|---|---|
| Identity | Owner / Manager / Staff; JWT auth from the scaffold; Manager pinned to one location, Owner across all four, Staff to their own records |
| Organization | 4 locations seeded, 29 typed rooms with `client_capacity` and `exclusive` (FRS §20) |
| Catalogue | The full FRS §19 menu — massage, facial, head spa, bioelectric, 30-min add-ons, enhancements — with per-location effective-dated prices |
| Workforce | Staff profiles, service qualifications, the six-rung session rate ladder, shifts |
| Scheduling | Availability engine (doc 03): multi-therapist, capacity-based room matching, 15-minute buffer inside the stored interval, 15-minute grid; booking with conflict prevention; lifecycle transitions; specific-therapist requests |
| Clients | Profiles, phone search, "Add New Client", preferences form |
| UI | Angular 21: sign-in, dashboard, day board, booking, clients, staff, shifts |

**Out — deliberately, and not started:** orders, payments, tips, gift cards, membership, earnings
and payout, ratings, notifications, reporting, data migration, and everything in Release 2. Each is
specified in docs 01–05 and derives from appointment data, which is why the scheduling core is
built first.

---

## 4. Build order

| Step | Work | Gate |
|---|---|---|
| 0 | Generate the app from the scaffold | `docker compose up` serves the stock app |
| 1 | Swap SQLite to WAL + `busy_timeout`; add the domain migrations | `db:prepare` clean |
| 2 | Seed locations, rooms, the full menu, staff, qualifications, rates, shifts | Seed is idempotent and matches FRS §19/§20 exactly |
| 3 | Roles, policies, location scoping | Manager cannot read another location; Staff cannot create appointments |
| 4 | Availability engine | Doc 03 §6.1 tests 11–17, 23, 24 |
| 5 | `Scheduling::BookAppointment` with `BEGIN IMMEDIATE` | Doc 03 §6.1 tests 1–9, 18–21 |
| 6 | Angular UI over the above | Browser-verified in Docker |
| 7 | Full test run + browser walkthrough | RSpec green; every screen exercised |

---

## 5. Rules this build must honour

Carried from doc 01 §7. These are the ones the scheduling core actually implements:

- **BR-08** therapists qualified, on shift, conflict-free **across all four locations**
- **BR-09 / BR-09a** room capacity sufficient, exclusive rooms respected, smallest sufficient room wins
- **BR-10** minimum 15-minute gap, same room and same therapist — carried inside `appointments.ends_at`
- **BR-11** price snapshotted at booking
- **BR-14** only Owner and Manager create appointments; Staff never
- **BR-15 / BR-15a** specific-therapist request holds the slot as `pending_approval`; auto-approve at 45 min after re-checking the therapist is still free
- **BR-16** unavailable requested therapist → that therapist's next time only, never a substitute
- **BR-17** only `completed` appointments generate revenue and earnings
- **BR-18 / BR-19** the 4-hour window; fee recorded as owed, profile-only
- **BR-21** status transition is the only way to release a resource
- **BR-42** clients are company-wide across all four locations

---

## 6. Test plan

The twenty-four scheduling tests in doc 03 §6.1 are the gate. Tests 10 and 22 are Release 2 (slot
holds, client channel) and are not in this build; the remaining twenty-two must pass.

**Four of them gate everything else** and are written first:

1. Concurrent booking of one slot from N threads → exactly one succeeds. *With the exclusion
   constraint gone this test is the guarantee, not a check on it.*
2. (test 11) Couples massage with only one free therapist is not offered — cardinality, not existence.
3. (test 12) Booking the second therapist into a taken slot rolls back the whole appointment.
4. (test 18) Two appointments 15 minutes apart both succeed; 10 minutes apart, the second is refused.

Browser verification in Docker Compose covers: sign-in as each role, the day board, booking a
single and a couples appointment, the buffer being enforced, a specific-therapist request and its
approval, client creation and search, and Manager location scoping.
