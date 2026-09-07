# 05 · Testing

## Running everything

```bash
docker compose run --rm test                          # RSpec
docker compose run --rm frontend npm run test:ci      # Vitest
```

## What must be tested

Non-negotiable:

- **Every API endpoint** — a request spec covering success, validation failure, and
  unauthenticated access.
- **Every service object** — a unit spec per public behaviour.
- **Every query object** — including the filtering/search edge cases.
- **Every Angular service** — with `HttpTestingController`.
- **Every guard and interceptor.**

Models get specs for validations and any non-trivial method — shoulda-matchers keeps
these to one line each.

## RSpec conventions

- **Request specs over controller specs.** Exercise the real routing, middleware, and
  serialization stack.
- FactoryBot for all test data. Factories stay minimal — no `after(:create)` side effects
  unless the test needs them; use traits for variation.
- `auth_headers(user)` from `spec/support/auth_helpers.rb` for authenticated requests.
- One expectation *concept* per example. Multiple `expect` lines about the same outcome
  are fine.
- Never assert on a hardcoded id; use the created record's id.

```ruby
it "rejects a note belonging to another user" do
  other = create(:note)

  get "/api/v1/notes/#{other.id}", headers: auth_headers(user)

  expect(response).to have_http_status(:not_found)
end
```

Add `spec/support/**` files for shared helpers; they are auto-required by `rails_helper`.

## Vitest conventions

Angular's built-in `@angular/build:unit-test` builder runs Vitest — there is no
`jest.config.ts`, no `jest-preset-angular`, and no separate setup file to maintain.

- `TestBed.configureTestingModule` with standalone components in `imports`.
- `provideHttpClient()` + `provideHttpClientTesting()`, then assert with
  `HttpTestingController` and always `http.verify()` in `afterEach`.
- Clear `localStorage` in `beforeEach` — the auth service reads it.
- The app is **zoneless**: `await fixture.whenStable()` after triggering async work.

```ts
it('stores the token on sign in', () => {
  service.signIn('demo@example.com', 'password123').subscribe();
  http.expectOne(`${environment.apiUrl}/auth/sign_in`).flush({ token: 't', user });
  expect(service.token).toBe('t');
});
```

## Database

The test database is prepared with the Rails-native task — never by hand:

```bash
bin/rails db:test:prepare
```

Specs run in transactions (`use_transactional_fixtures`), so they do not leak state.
