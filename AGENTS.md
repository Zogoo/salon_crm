# AGENTS.md — Mongolian Massagelab

**Read `docs/` before making changes.** These files are the contract for how work is done
in this repository, for AI agents and humans alike.

| Doc | Read it when |
|---|---|
| [docs/engineering/00-agent-persona.md](docs/engineering/00-agent-persona.md) | Always — first. Defines how you work and the definition of done. |
| [docs/engineering/01-tech-stack.md](docs/engineering/01-tech-stack.md) | Considering any dependency, or touching the DB. |
| [docs/engineering/02-architecture.md](docs/engineering/02-architecture.md) | Adding an endpoint, service, query, or component. |
| [docs/engineering/03-coding-standards.md](docs/engineering/03-coding-standards.md) | Writing any code. |
| [docs/engineering/04-security-owasp.md](docs/engineering/04-security-owasp.md) | Touching auth, params, uploads, or SQL. |
| [docs/engineering/05-testing.md](docs/engineering/05-testing.md) | Writing tests — which is every behaviour change. |
| [docs/engineering/06-workflows.md](docs/engineering/06-workflows.md) | Running commands, migrations, i18n, deploys. |

## Domain documentation

`docs/engineering/` above is *how* to build. `docs/` itself is *what* to build — the business
analysis and architecture for this system. Read before touching domain code:

| File | Read when |
|---|---|
| [docs/00-README.md](docs/00-README.md) | Orientation — start here. |
| [docs/08-build-plan.md](docs/08-build-plan.md) | **Always, before any domain change.** Stack decisions, what is in scope, and why booking conflicts are handled in application code. |
| [docs/01-business-analysis.md](docs/01-business-analysis.md) | Any rule question — 52 numbered business rules. |
| [docs/02-domain-model.md](docs/02-domain-model.md) | Any schema or migration change. |
| [docs/03-scheduling-engine.md](docs/03-scheduling-engine.md) | **Any change to availability or booking.** |
| [docs/05-api-design.md](docs/05-api-design.md) | Adding or changing an endpoint. |

## The short version

- Senior Rails + Angular engineer. Boring, proven, tested.
- **Rails-native-first**: if Rails already does it, do not add a gem.
- **Nothing JS in Rails**: the SPA is Angular's, exclusively.
- **Never** `rails generate scaffold`; never hand-write a migration.
- **Always** scope records through `current_user`.
- Tests, RuboCop, Brakeman, bundler-audit green before done.

## Layout

```
app/{controllers,models,services,queries,jobs,mailers}   # thin → service → query → model
spec/                                                    # RSpec
frontend/src/app/{core,features,shared}                  # Angular standalone + signals
docs/                                                    # you are here
```
