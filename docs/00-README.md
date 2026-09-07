# Mongolian Massagelab — Business Analysis & Architecture

Design package for the four-location management platform. **No implementation has started.**

**This is an internal management tool first.** Release 1 is operated entirely by Owner, Manager and
Therapist inside the four locations — scheduling, clients, gift cards, payments recorded at the
desk, therapist earnings and reporting. Client self-service booking, Stripe payment collection and
online gift card purchase are **specified in full across these documents but deferred to Release
2**, so the design is settled without the build carrying it. See doc 06 §1 for the split and for
the two business rules that degrade in the meantime.

**Source of truth:** [`business_requirement.md`](business_requirement.md) — the owner's Functional
Requirements Specification, v7, 21 Aug 2026, together with the owner's subsequent decisions on the
points it left open, which are folded into these documents as rules. Where a document disagrees
with the FRS or with a stated owner decision, the document is wrong; please report it.

**Version 1.1** · 2026-09-01 · pre-implementation.

## Documents

| # | Document | Contents |
|---|---|---|
| 01 | [Business Analysis](01-business-analysis.md) | Actors, the access matrix, separation of duties, 10 core processes, appointment lifecycle, gift cards, membership, earnings, reporting, NFRs, **48 numbered business rules**, 4 risks raised by the spec |
| 02 | [Domain Model](02-domain-model.md) | 13 bounded contexts, 5 Mermaid ERDs, full entity dictionary, **18 database-enforced invariants**, money/time conventions, indexing plan |
| 03 | [Scheduling Engine](03-scheduling-engine.md) | The 13 availability conditions, the 5-phase search, multi-therapist pairing, capacity-based room matching, assignment policy, **concurrency and double-booking prevention**, timezone & DST rules, performance budget, **24 gating tests** |
| 04 | [System Architecture](04-system-architecture.md) | Modular monolith rationale, Rails + AngularJS layout, three bundles, auth for staff and clients, the full permission matrix, **payments architecture**, notifications, background jobs, reporting, deployment, **16 ADRs** |
| 05 | [API Design](05-api-design.md) | ~110 REST endpoints across 14 groups, error codes, payload examples, the public surface, and what is deliberately not exposed |
| 06 | [Delivery Roadmap](06-delivery-roadmap.md) | The internal-first posture and what deferral costs · **Release 1 (internal, ~11–15 weeks)** in five phases with exit criteria · **Release 2 (client-facing, ~6–8 weeks)** in three |
| 07 | [Limitations & Risks](07-open-questions-and-risks.md) | 4 accepted limitations, 22-row risk register, pre-implementation definition of done |
| 08 | [Build Plan](08-build-plan.md) | **The implementation stack and where it overrides docs 02–05**, the SQLite downgrade stated plainly, scope of the scheduling-core build, build order, test gate |

## Confirmed decisions

Four fixed locations (Lawrence, Skokie, Luma, Belmont) · all US Central · Rails API + AngularJS in
one project · PostgreSQL · Owner / Manager / Staff / Client, **one Manager per location** ·
therapists are **1099 contractors paid per completed session** across a six-rung ladder
(30/45/60/75/90/120 min) · Managers on a flat monthly rate · an appointment is **1 room + 1–2
therapists** · rooms match **by client capacity**, head-spa rooms exclusive · **15-minute buffer,
15-minute grid, 6-month horizon** · in-salon payments **recorded** through the existing terminal ·
gift cards redeemable across all four locations and **never forfeited at expiry** · memberships
**tied to their joining location** · email **and** SMS, with reminders at **24 h and 2 h** ·
peak sizing **100 appointments/location/day** · English only at launch · packages, health intake
and SOAP notes all out of scope.

**Release 2, designed but not scheduled:** client accounts and self-service booking · Stripe for
20% deposits, automatic 20% no-show/late-cancel fees and the $80/month membership subscription ·
online gift card purchase.

## The five decisions that matter most

1. **Double-booking prevention is the system's load-bearing guarantee.** It was designed as
   Postgres exclusion constraints; the implementation stack is SQLite, so it is now application
   code inside `BEGIN IMMEDIATE`, concentrated in one service object. Room conflicts are
   location-scoped; therapist conflicts are company-wide. **This is a downgrade and doc 08 §2 says
   why.** See doc 03 §4, ADR-08, ADR-17.
2. **The 15-minute buffer lives inside the stored appointment interval.** The gap rule from FRS §21
   then falls out of the same constraints — one mechanism, not two. See doc 03 §1.1 and ADR-09.
3. **Rates, prices, gift card balances and membership credits are effective-dated or ledger-based,
   never mutable.** This is what makes past earnings statements and past revenue reports
   reproducible. See BR-11, BR-25, BR-35.
   *Therapist pay combines a base session and its add-on into one rung when the total lands on one
   — a 60+30 pays as a single 90 — and falls back to per-item only when it does not. See BR-33.*
4. **A gift card sale and a membership charge are liabilities, not revenue.** Revenue is recognised
   on redemption; fees are a third category. This is the most common accounting error in salon
   systems. See BR-26, BR-41, BR-48.
5. **Release 1 ships no client-facing surface, but is built to receive one.** The scheduling core,
   earnings and gift cards deliver value on their own; client booking and payment add a third-party
   dependency and a public attack surface to a system that has not yet proven itself in daily use.
   The schema, policies, API versioning and bundle split all already accommodate Release 2, so it
   is an addition rather than a rewrite. See ADR-16, and ADR-10 for why Stripe stays online-only
   even then.

## Next step

**No open questions remain.** Every point FRS v7 left unsettled has been answered and folded into
these documents as rules. Phase 0 can start; the pre-implementation checklist is doc 07 §4.

One decision is worth making **before go-live rather than after**: whether each Manager gets an
individual login. The current answer is one shared login per location, which means the audit trail
can name the front desk but never a person — and unlike every other choice here, that attribution
**cannot be reconstructed retroactively**. See doc 07 §2.
