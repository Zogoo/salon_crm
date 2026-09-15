# Deployment

```
push to main ──> Fly Deploy workflow
                  ├─ CI (reusable ci.yml)
                  │   ├─ Brakeman + bundler-audit
                  │   ├─ RuboCop
                  │   ├─ RSpec
                  │   ├─ Prettier + Vitest
                  │   └─ E2E: production image + Playwright   (bin/e2e)
                  └─ all green ──> deploy ──> flyctl deploy --remote-only
```

`.github/workflows/fly-deploy.yml` runs on every push to `main` and on the
manual **Run workflow** button. It calls the CI workflow as a job, and `deploy`
`needs` it, so a commit ships only if every CI job passed **in that same run**,
including the end-to-end suite. There is no path that skips the tests: the
manual button runs them too, and a manual run from any branch other than
`main` tests but never deploys.

Pull requests and other branches run `ci.yml` directly, so the same checks show
on the PR before merge. To make them required, add them under **Settings →
Branches → Branch protection rules → main → Require status checks** (the job
names are `scan_ruby`, `lint`, `test`, `test_frontend` and `e2e`).

## The end-to-end gate

`bin/e2e` is the QA gate, and it is the same script locally and in CI:

1. builds the production `Dockerfile` (Angular build + Rails, exactly what Fly
   runs);
2. boots it with `RAILS_ENV=production`, a fresh SQLite file and throwaway
   secrets. `bin/docker-entrypoint` runs `db:prepare`, which also seeds, as on
   a first Fly boot. `RAILS_FORCE_SSL=false`/`RAILS_ASSUME_SSL=false` let it
   serve plain http without a TLS proxy (Fly sets both to `true`);
3. runs the Playwright suite in `e2e/` from the official Playwright image,
   against that container.

The suite covers sign-in and role boundaries, booking with no preference and
assignment, deposit, Manager discount (and its limit), rating (and declining to
rate), one-step checkout, payment and settlement, cancelling, no-shows,
drag-and-drop moves, the discount limit setting, gift card codes, the audit
log, the revenue report and amount-only earnings entries.

```bash
bin/e2e                        # build the image and run everything
E2E_SKIP_BUILD=1 bin/e2e -g checkout   # reuse the image, run matching tests
```

A failed CI run uploads `e2e-report` (Playwright HTML report with traces,
screenshots and video, plus the app log).

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
