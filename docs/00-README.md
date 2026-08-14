# Massage Salon CRM — Business Analysis & Architecture

Design package. **No implementation has started**, per your instruction.

## Documents

| # | Document | Contents |
|---|---|---|
| 01 | [Business Analysis](01-business-analysis.md) | Actors, separation of duties, 9 core business processes, appointment lifecycle, gift card lifecycle, reporting requirements, NFRs, **28 numbered business rules** |
| 02 | [Domain Model](02-domain-model.md) | Bounded contexts, 5 Mermaid ERDs, full entity dictionary with columns, 12 database-enforced invariants, money/time conventions, indexing plan |
| 03 | [Scheduling Engine](03-scheduling-engine.md) | The 10 availability conditions, the 5-phase search algorithm, assignment policy, **concurrency/double-booking prevention**, timezone & DST rules, performance budget, 10 gating tests |
| 04 | [System Architecture](04-system-architecture.md) | Modular monolith rationale, Rails + AngularJS project layout, module structure, auth & the full permission matrix, PHI protection, background jobs, reporting, deployment, 10 ADRs |
| 05 | [API Design](05-api-design.md) | ~90 REST endpoints across 12 groups, error codes, payload examples, public endpoint surface |
| 06 | [Roadmap & Open Questions](06-roadmap-and-open-questions.md) | 6-phase plan (~10–15 weeks), **17 assumptions to confirm**, **17 open questions**, risk register |

## Confirmed decisions

Single company, 2–10 locations · Rails API + AngularJS in one project · PostgreSQL · payments
**recorded, not processed** (cash/card/Zelle/online) · 1 appointment = 1 room + 1 therapist · staff
work at any location · hourly pay from scheduled shift hours · 4 roles · booking via phone,
walk-in, online self-service and staff self-service · gift cards in three variants · email
notifications · single cloud server.

## The three decisions that matter most

1. **Double-booking is prevented by Postgres exclusion constraints, not application code.**
   Therapist conflicts are checked company-wide (staff work at any location); room conflicts are
   location-scoped. See doc 03 §4.
2. **Rates, prices and gift card balances are effective-dated or ledger-based, never mutable.**
   This is what makes past payroll and past revenue reports reproducible. See BR-18, BR-24, BR-26.
3. **A gift card sale is a liability, not revenue.** Revenue is recognised on redemption. This is
   the most common accounting error in salon systems. See BR-19.

## Next step

Answer **OQ-01 through OQ-05** in doc 06 §3 — they are the five questions that would change the
architecture rather than just the implementation.
