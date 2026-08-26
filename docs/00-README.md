# Mongolian Massagelab — Business Analysis & Architecture

Design package for the four-location management platform. **No implementation has started.**

**Source of truth:** [`business_requirement.md`](business_requirement.md)
— the owner's Functional Requirements Specification, v7, 21 Aug 2026.
These six documents translate it into an architecture. Where they disagree, the FRS wins and the
document is wrong; please report it.

**Version 1.0** · 2026-08-26 · pre-implementation.

## Documents

| # | Document | Contents |
|---|---|---|
| 01 | [Business Analysis](01-business-analysis.md) | Actors, the access matrix, separation of duties, 10 core processes, appointment lifecycle, gift cards, membership, earnings, reporting, NFRs, **48 numbered business rules**, 4 risks raised by the spec |
| 02 | [Domain Model](02-domain-model.md) | 13 bounded contexts, 5 Mermaid ERDs, full entity dictionary, **18 database-enforced invariants**, money/time conventions, indexing plan |
| 03 | [Scheduling Engine](03-scheduling-engine.md) | The 13 availability conditions, the 5-phase search, multi-therapist pairing, assignment policy, **concurrency and double-booking prevention**, timezone & DST rules, performance budget, **20 gating tests** |
| 04 | [System Architecture](04-system-architecture.md) | Modular monolith rationale, Rails + AngularJS layout, three bundles, auth for staff and clients, the full permission matrix, **payments architecture**, notifications, background jobs, reporting, deployment, **15 ADRs** |
| 05 | [API Design](05-api-design.md) | ~110 REST endpoints across 14 groups, error codes, payload examples, the public surface, and what is deliberately not exposed |
| 06 | [Roadmap & Open Questions](06-roadmap-and-open-questions.md) | 7-phase plan (~15–20 weeks), **17 assumptions**, **15 open questions**, risk register, definition of done |

## Confirmed decisions

Four fixed locations (Lawrence, Skokie, Luma, Belmont) · all US Central · Rails API + AngularJS in
one project · PostgreSQL · Owner / Manager / Staff / Client, **one Manager per location** ·
therapists are **1099 contractors paid per completed session** across a six-rung ladder
(30/45/60/75/90/120 min) · Managers on a flat monthly rate · an appointment is **1 room + 1–2
therapists** · rooms are **typed** · **15-minute buffer, 15-minute grid, 6-month horizon** ·
in-salon payments **recorded** through the existing terminal, online payments **processed by
Stripe** (20% deposit, 20% no-show/late-cancel fee, $80/month membership) · gift cards redeemable
across all four locations · email **and** SMS · client accounts required for self-booking ·
packages, health intake and SOAP notes all out of scope.

## The five decisions that matter most

1. **Double-booking is prevented by Postgres exclusion constraints, not application code.**
   With two-therapist services the therapist constraint moves to `appointment_staff`, which is why
   that table carries a denormalised interval and status. Room conflicts are location-scoped;
   therapist conflicts are company-wide. See doc 03 §4 and ADR-08.
2. **The 15-minute buffer lives inside the stored appointment interval.** The gap rule from FRS §21
   then falls out of the same constraints — one mechanism, not two. See doc 03 §1.1 and ADR-09.
3. **Rates, prices, gift card balances and membership credits are effective-dated or ledger-based,
   never mutable.** This is what makes past earnings statements and past revenue reports
   reproducible. See BR-11, BR-25, BR-35.
4. **A gift card sale and a membership charge are liabilities, not revenue.** Revenue is recognised
   on redemption; fees are a third category. This is the most common accounting error in salon
   systems. See BR-26, BR-41, BR-48.
5. **Stripe handles online money only; the existing card terminal keeps in-salon checkout.** That
   holds PCI scope at SAQ-A while still supporting deposits, automatic fee charges and a monthly
   subscription. See ADR-10.

## Next step

Answer **OQ-01** (how an add-on pays the therapist) and **OQ-02** (whether Staff may enter a
walk-in, where FRS §2 contradicts §3 and §21) in doc 06 §3 — they gate Phase 1. Then raise
**RISK-01** (the 12-month gift card expiry) with counsel, and answer **OQ-10** (whether the
platform pays therapists or only reports what is owed).
