# Deployment

```
push to main ──> CI (Brakeman, bundler-audit, RuboCop, RSpec, Vitest)
                  └─ green ──> Fly Deploy ──> flyctl deploy --remote-only
```

`.github/workflows/fly-deploy.yml` runs on `workflow_run` after CI completes on
`main`, and only when CI concluded `success`. It checks out
`workflow_run.head_sha`, so the commit that went green is the commit that ships,
even if `main` has moved on. A red CI run deploys nothing.

`workflow_dispatch` on the same workflow gives a manual deploy button, which is
also the way to re-deploy the current `main` after a rollback.

Everything below is one-time setup. Once it is done, no manual step is needed to
release.

## 1. Create the app and its volume

The app name and region must match [fly.toml](../../fly.toml) (`massagelab`,
`ord`). SQLite lives on the volume, so the volume has to exist before the first
deploy.

```bash
fly apps create massagelab --org personal
fly volumes create database_storage --app massagelab --region ord --size 1 --yes
```

## 2. Set the production secrets

Non-secret configuration lives in the `[env]` block of `fly.toml` and is
committed. Only these two are secrets, and both are required:

| Secret | Why |
| --- | --- |
| `RAILS_MASTER_KEY` | Decrypts `config/credentials.yml.enc` and derives `secret_key_base`. |
| `JWT_SECRET` | `Auth::JwtService` raises on boot in production without it. |

```bash
fly secrets set --app massagelab \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  JWT_SECRET="$(openssl rand -hex 32)"
```

Mail is optional and off by default; `SMTP_ADDRESS`, `SMTP_PORT`,
`SMTP_USERNAME` and `SMTP_PASSWORD` are Fly secrets too when you want real
delivery. See [.env.example](../../.env.example) for the full variable list.

## 3. First deploy, by hand

Do the first one locally so the failure output is in front of you.
`--ha=false` keeps it to a single machine: there is one volume and one SQLite
file, so a second machine would boot without a database.

```bash
fly deploy --ha=false
```

Migrations are not a deploy step. `bin/docker-entrypoint` runs `db:prepare`
before Puma boots, which creates the schema on the empty volume the first time
and migrates on every later boot.

## 4. Give CI a deploy token

```bash
fly tokens create deploy -a massagelab
```

Add the output as a repository secret named `FLY_API_TOKEN` under
**Settings → Secrets and variables → Actions**. The deploy job also names a
`production` environment; GitHub creates it on the first run, and required
reviewers can be added there if you want deploys to pause for approval.

## Operating notes

- **One machine, on purpose.** SQLite on a Fly volume cannot be scaled out.
  Do not `fly scale count` above 1.
- **Machines stop when idle.** `min_machines_running = 0` with
  `auto_start_machines`, so the first request after a quiet period pays a cold
  start.
- **Console.** `fly console` starts an ephemeral machine *without* the volume.
  Use `fly ssh console -C '/app/bin/rails console'` to reach the real database.
- **Rollback.** `fly releases -a massagelab` then
  `fly deploy --image <previous image ref>`. Roll the code back on `main` after,
  or the next green CI run redeploys what you just rolled out of.
- **Uploads.** `ACTIVE_STORAGE_SERVICE` is `local` in `fly.toml`, which puts
  attachments on the same volume. Provision a Tigris bucket and flip it to `fly`
  before uploads matter.
