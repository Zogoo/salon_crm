# Mongolian Massagelab

Rails 8.1 API + Angular 21 SPA, SQLite, deployable to a single
Fly.io machine.

## Requirements

Docker and Docker Compose. Nothing else — Ruby and Node run inside containers.

## Getting started

```bash
docker compose up
```

| Service | URL |
|---|---|
| API | http://localhost:3011 |
| App | http://localhost:4211 |
| Mailpit (email) | http://localhost:8035 |
| MinIO console | http://localhost:9011 |

Seed a demo account:

```bash
docker compose run --rm backend bin/rails db:seed
# demo@mongolianmassagelab.com / password123
```

## Tests and checks

```bash
docker compose run --rm test                       # RSpec
docker compose run --rm frontend npm run test:ci   # Vitest
docker compose run --rm backend bin/rubocop
docker compose run --rm backend bin/brakeman
docker compose run --rm backend bin/bundler-audit
```

## Structure

```
app/controllers/api/v1/   # JSON endpoints
app/services/             # business logic, one public .call
app/queries/              # read models
frontend/src/app/core/    # services, guards, interceptors
frontend/src/app/features/# auth, notes, dashboard
docs/                     # engineering contract — read this first
```

`notes` is the example resource, wired end to end (Rails model → controller → spec,
Angular service → component → spec). Replace it with your own domain.

## Environment

Every variable is documented in [.env.example](.env.example). Development values are set
directly in `docker-compose.yml`; production values are Fly secrets.

## Deploying

Every green CI run on `main` deploys itself, once the app is provisioned and the
`FLY_API_TOKEN` repository secret is set. `fly.toml` is committed and ready; the one-time
setup is in [docs/engineering/07-deployment.md](docs/engineering/07-deployment.md).

## Conventions

See [AGENTS.md](AGENTS.md) and [docs/](docs/). Short version: Rails-native-first, nothing
JS in Rails, always scope by `current_user`, tests green before done.
