# 04 · Security (OWASP Top 10 → this codebase)

Every change touching auth, params, uploads, or SQL gets an explicit pass over this file.

## A01 · Broken access control

- `ApplicationController` runs `authenticate!` as a `before_action` for **every** action.
  Public endpoints opt out explicitly and visibly:
  `skip_before_action :authenticate!, only: %i[sign_in sign_up]`.
- **Always scope by the current user.** `current_user.notes.find(params[:id])`, never
  `Note.find(params[:id])`. This is the single most common way to ship an IDOR here.
- New nested resource? Scope it through its owner association too.

## A02 · Cryptographic failures

- Passwords: `has_secure_password` (bcrypt). Never store, log, or return a password.
- JWT: HS256, secret from `JWT_SECRET`, `exp` set on encode and **verified** on decode.
  In production `JWT_SECRET` is required and the app raises without it.
- Secrets live in env vars / Rails credentials / `fly secrets`. Never in a tracked file.
  `config/master.key` is gitignored and must stay that way.

## A03 · Injection

- SQL: Active Record with bind parameters only. `where("title LIKE :q", q: pattern)` —
  never string interpolation into a query.
- `NotesQuery` escapes `%`, `_` and `\` in LIKE terms before building the pattern. Any new
  LIKE search must do the same.
- Never pass user input to `order(...)` without an allowlist of column names.

## A04 · Insecure design

- Business rules belong in services with specs, not in controllers where they get skipped
  by the next caller.
- Rate limiting is **not** implemented. Before exposing sign-in publicly at scale, add
  `Rack::Attack` or Fly-level limits — this is a known, accepted gap.

## A05 · Security misconfiguration

- `config.force_ssl` and `assume_ssl` are on in production.
- CORS is off unless `CORS_ORIGINS` is set, and is scoped to `/api/*` only. Never set it
  to `*` in production.
- `config.consider_all_requests_local = false` in production — no error detail leaks.

## A06 · Vulnerable components

- `bin/bundler-audit` and `bin/brakeman` run in CI and must stay green.
- Dependabot is configured. Security updates get merged, not deferred.

## A07 · Identification & authentication failures

- Minimum password length is enforced in the model (8 characters).
- Sign-in failures return a generic message — never reveal whether the email exists.
- Tokens expire in 24h. The Angular `errorInterceptor` signs out on 401.
- **Token storage**: the token is in `localStorage`, which is XSS-readable. This is the
  accepted trade-off for a stateless API with no cookie/CSRF machinery. The mitigation is
  strict output escaping — Angular escapes by default, so **never** use `innerHTML` or
  `bypassSecurityTrust*` with user content.

## A08 · Software & data integrity

- Uploads are validated server-side in `User#acceptable_avatar` — content type allowlist
  and size cap. Client-declared types are not trusted.
- `Gemfile.lock` and `package-lock.json` are committed; CI installs with `npm ci`.

## A09 · Logging & monitoring failures

- `config/initializers/filter_parameter_logging.rb` filters passwords and tokens. Add any
  new sensitive param name there.
- Never `Rails.logger.info` a token, password, or full user record.

## A10 · SSRF

- The app makes no outbound requests from user input. If you add one, validate the host
  against an allowlist — do not fetch arbitrary user-supplied URLs.
