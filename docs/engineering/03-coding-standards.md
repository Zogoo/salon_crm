# 03 · Coding standards

## KISS

Write the simplest thing that works.

- No abstraction until there is a second real caller.
- No configuration option until someone needs to configure it.
- No `Base*` class with one subclass.
- Delete code rather than commenting it out — git remembers.

## DRY (rule of three)

Duplication is cheaper than the wrong abstraction. Extract on the **third** occurrence,
not the second.

- Rails: extract to a service object (behaviour) or a query object (reads).
- Angular: extract to a service (state/HTTP) or a shared component (markup).

## SOLID, concretely

| Principle | What it means here |
|---|---|
| **S**RP | A service does one thing and is named after it: `Auth::AuthenticateUser`, not `UserManager`. |
| **O**CP | Add a new query object rather than adding a sixth boolean flag to an existing one. |
| **L**SP | A subclass of `ApplicationQuery` still returns a relation from `call`. Don't return an array. |
| **I**SP | Controllers depend on a service's `.call`, not on a grab-bag object with twelve methods. |
| **D**IP | Pass collaborators in: `initialize(email:, password:)`, and Angular constructor/`inject()` DI. Don't reach for globals. |

## Non-negotiable tooling

- **RuboCop** (`rubocop-rails-omakase`) — `bin/rubocop` must be clean.
- **Prettier** — `npm run lint` in `frontend/` must be clean.

Both are formatters, not opinions to debate. Run `bin/rubocop -a` and `npm run format`.

## Naming

- Services: verb phrase, namespaced — `Auth::AuthenticateUser`, `Notes::ArchiveNote`.
- Queries: `<Resource>Query` — `NotesQuery`.
- Angular components: noun, `PascalCase` class in a `kebab-case.ts` file — `SignIn` in `sign-in.ts`.
- Booleans read as predicates: `signed_in?`, `isSignedIn`.
- No abbreviations except the universally known ones (`id`, `url`, `jwt`).

## Ruby specifics

- Prefer `private` methods over long public surfaces.
- Guard clauses over nested conditionals.
- `find_by` returns nil and you must handle it; `find` raises and `ApplicationController`
  already renders 404.
- Strong params always — never `params.permit!`.

## Angular specifics

- Standalone components only. No NgModules.
- Signals for component state; `computed` for derived state.
- `inject()` over constructor injection in new code.
- Native control flow (`@if`, `@for`, `@switch`) — not `*ngIf` / `*ngFor`.
- `track` is mandatory in `@for`.
- No `any`. If a type is genuinely unknown, use `unknown` and narrow it.

## Commits

```
<type>: <imperative summary under 72 chars>

<why, if it isn't obvious from the diff>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. One logical change per commit.
