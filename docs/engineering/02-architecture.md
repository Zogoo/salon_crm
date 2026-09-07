# 02 · Architecture

## Request flow

**Development** — two origins, CORS in between:

```
Browser :4211  ──HTTP──>  Angular dev server (ng serve)
        │
        └──XHR──>  http://localhost:3011/api/v1  ──>  Rails (rack-cors)
```

**Production** — one origin, no CORS:

```
Browser ──> Fly proxy ──> Puma :3000
                            ├── /api/v1/*  ──> Rails controllers
                            ├── /up        ──> health check
                            └── everything else ──> public/index.html (SpaController)
```

The production Docker build compiles Angular and copies `dist/frontend/browser` into
`public/`. `ActionDispatch::Static` serves the files; `SpaController#index` is the
catch-all for client-side routes. The catch-all deliberately excludes `/api/`, `/up`,
and any path with a file extension.

## Layering

Strict, and enforced in review:

```
Controller  →  thin. Params in, JSON out, HTTP status. No business logic.
Service     →  business logic. One public entry point: `.call`. Inherits ApplicationService.
Query       →  read models. Wraps a relation, returns a relation. Inherits ApplicationQuery.
Model       →  validations, associations, scopes, normalization. No orchestration.
```

Rules:

- A controller action that is more than ~10 lines is doing a service's job.
- Business logic never lives in a model callback that touches other aggregates.
- Anything that reads with filters/search/sorting belongs in a query object, not in the
  controller and not as an ever-growing model scope.
- Services do not know about `params` or HTTP; pass them plain arguments.

## Authentication flow

```
POST /api/v1/auth/sign_up ─┐
POST /api/v1/auth/sign_in ─┴─> Auth::AuthenticateUser ──> Auth::JwtService.encode
                                                              │
                                        { token, user } <─────┘

Every other request:
  Authorization: Bearer <token>
      └─> Authenticatable#authenticate! ──> Auth::JwtService.decode ──> current_user
```

- HS256, secret from `JWT_SECRET`, 24h expiry, `sub` = user id, `exp` always verified.
- `ApplicationController` calls `authenticate!` in a `before_action` for **every** action.
  Public endpoints must opt out explicitly with `skip_before_action`.
- The Angular side stores the token and attaches it via `authInterceptor`;
  `errorInterceptor` signs the user out on a 401 so expired tokens self-heal.

## Active Storage flow

```
dev   → S3 service `fly` pointed at MinIO   (docker compose, bucket massagelab-files)
test  → Disk service, tmp/storage
prod  → S3 service `fly` pointed at Tigris  (AWS_* secrets set by `fly storage create`)
```

Uploads are validated in the model (`User#acceptable_avatar`: content type + size) — never
trust the client's declared type.

## Mail flow

```
dev  → SMTP to Mailpit (UI on :8035)
test → :test delivery method, assert on ActionMailer::Base.deliveries
prod → SMTP via SMTP_* env vars
```

Mail is always sent from a job (`deliver_later`) so a slow SMTP server never blocks a
request. The `:async` Active Job adapter runs it in-process — acceptable at this scale,
and it means no Redis.
