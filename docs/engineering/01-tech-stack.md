# 01 · Tech stack

Everything here was chosen to be **cheap to run** and **boring to maintain**.

## Backend

| Concern | Choice |
|---|---|
| Framework | Rails 8.1, `config.api_only = true` |
| Ruby | 3.4.10 (see `.ruby-version`) |
| Database | SQLite 3, path from `DATABASE_PATH` |
| Server | Puma, binds `0.0.0.0:$PORT` |
| Auth | `jwt` + `bcrypt`, hand-rolled — no Devise |
| Pagination | `pagy` |
| CORS | `rack-cors`, active only when `CORS_ORIGINS` is set |
| Files | Active Storage → Disk (test/dev) and S3 service `fly` (MinIO dev, Tigris prod) |
| Mail | Action Mailer → Mailpit in dev, SMTP in production |
| Background work | Active Job `:async` adapter — no Redis, no Sidekiq |
| Tests | RSpec, FactoryBot, Faker, shoulda-matchers |
| Quality | rubocop-rails-omakase, Brakeman, bundler-audit |

## Frontend

| Concern | Choice |
|---|---|
| Framework | Angular 21, standalone components, signals, zoneless |
| i18n | `@ngx-translate/core`, JSON in `src/assets/i18n/` |
| Tests | **Vitest**, via Angular's built-in `@angular/build:unit-test` builder |
| Styling | SCSS, plain CSS variables — no UI framework |
| Dev server | `ng serve` in Docker with `--poll` |

## Deployment

Single Fly.io machine, `shared-cpu-1x` / 512MB, `min_machines_running = 0`,
`auto_stop_machines`. SQLite lives on a mounted volume. This is the cheapest
configuration that still serves real traffic.

## Hard rules

### Rails-native-first

**Use built-in Rails features wherever Rails already supports the need.** Active Job,
Active Storage, Action Mailer, Rails credentials, Rails caching, `has_secure_password`,
validations, `normalizes`. If Rails already does it, an external gem is rejected by
default. A new gem needs a written justification in the PR description.

**The single exception is JavaScript**: nothing JS-related happens in Rails. No Hotwire,
Turbo, Stimulus, importmap, jsbundling, or asset pipeline. The SPA is Angular's job and
Rails only serves the built output from `public/`.

### SQLite implications

SQLite is the database — **design accordingly**:

- One writer at a time. Do not build concurrent-writer patterns or job fan-out that
  writes from many workers.
- Keep transactions short.
- No Postgres-only features: no `jsonb` operators, no array columns, no `ILIKE`
  (use `LIKE`, which is already case-insensitive for ASCII in SQLite).

### Cold starts

`min_machines_running = 0` means the first request after idle pays a cold start
(a few seconds). This is an accepted trade-off for cost. Do not "fix" it by keeping a
machine warm without a deliberate decision — that changes the bill.
