# 06 · Day-to-day workflows

## Commands

```bash
docker compose up                                  # full stack
docker compose run --rm test                       # RSpec
docker compose run --rm frontend npm run test:ci   # Vitest
docker compose run --rm backend bin/rubocop        # lint Ruby
docker compose run --rm backend bin/brakeman       # security scan
docker compose run --rm backend bin/bundler-audit  # gem CVEs
docker compose run --rm frontend npm run lint      # Prettier check
```

| Service | URL |
|---|---|
| API | http://localhost:3011 |
| App | http://localhost:4211 |
| Mailpit | http://localhost:8035 |
| MinIO console | http://localhost:9011 |

## Changing the schema

**Always through Rails generators. Never hand-write a migration file or edit `schema.rb`.**

```bash
docker compose run --rm backend bin/rails generate migration AddArchivedAtToNotes archived_at:datetime
docker compose run --rm backend bin/rails db:migrate
```

For a whole new resource:

```bash
docker compose run --rm backend bin/rails generate model Project name:string user:references
```

`config.generators` is configured to emit only the model, migration, spec and factory —
no helpers, assets, views, or jbuilder. **Never** use `rails generate scaffold`.

Database lifecycle uses the built-in tasks only: `db:create`, `db:prepare`, `db:migrate`,
`db:test:prepare`, `db:seed`.

## Adding an API endpoint

Work the checklist in order:

1. **Route** — `config/routes.rb`, inside `namespace :api { namespace :v1 }`.
2. **Controller** — thin action; scope through `current_user`.
3. **Service** — business logic, if the action does more than a find/render.
4. **Query** — if it reads with filters, search, or sorting.
5. **Request spec** — success, validation failure, unauthenticated, and cross-user access.
6. **Angular service** — a typed method in `core/services/`.
7. **Component** — feature under `src/app/features/`.
8. **Vitest spec** — for the service, and for the component if it has logic.
9. **i18n** — add keys to **every** file in `frontend/src/assets/i18n/`.

## Background work

Use Active Job — it is already configured with the `:async` adapter.

```ruby
UserMailer.welcome(user).deliver_later
SomeJob.perform_later(record.id)
```

Pass **ids, not objects**, and re-find inside the job. Do not add Sidekiq or Redis; see
the Rails-native-first rule in [01-tech-stack.md](01-tech-stack.md).

## i18n

- Backend strings: `config/locales/<locale>.yml`, referenced with `I18n.t`.
- Frontend strings: `frontend/src/assets/i18n/<locale>.json`, used via the `translate` pipe.
- A key added to one locale must be added to **all** of them. A missing key is a bug.

## Deploying

```
push to main ──> GitHub Actions CI ──> fly-deploy.yml ──> fly deploy
```

CI must be green: Brakeman, bundler-audit, RuboCop, RSpec, Vitest.

First-time setup (creates the app, volume, storage and secrets) is
`rake fly:setup` from the generator project. It is idempotent. Requires the
`FLY_API_TOKEN` repository secret for the deploy workflow.

Migrations run automatically on boot via `bin/docker-entrypoint` (`db:prepare`).
