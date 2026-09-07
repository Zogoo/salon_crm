# API Design

**Version:** 1.0 · `/api/v1` · JSON · session-cookie authenticated · same-origin
**Aligned to:** FRS v7

> **Stack note.** The client is **Angular 21** (standalone components), not AngularJS — see doc 08
> §1. The endpoint surface, error vocabulary and payload shapes below are unaffected.

> **Delivery posture.** Release 1 exposes the staff console surface only. Everything under
> `/api/v1/public/*`, the Stripe endpoints and the client half of §3 are **Release 2** and are
> marked. The `/api/v1` versioning and the error vocabulary are settled now so the client surface
> is an addition, not a break.

---

## 1. Conventions

| Aspect | Convention |
|---|---|
| Base path | `/api/v1` |
| Content type | `application/json` |
| Auth | httpOnly session cookie + `X-CSRF-Token` header on writes |
| Timestamps | ISO 8601 **with offset**: `2026-08-15T15:30:00-05:00` |
| Money | integer cents, field suffix `_cents` |
| Percentages | integers (`20` = 20%) |
| IDs | numeric internally; public-facing objects also expose `reference` / `code` |
| Pagination | `?page=1&per_page=25`; envelope carries `meta.total`, `meta.pages` |
| Filtering | explicit query params only, no generic query DSL |
| Errors | RFC 7807-ish body, see §2 |
| Idempotency | `Idempotency-Key` honoured on `POST /appointments`, `/payments`, `/gift_cards`, `/memberships` |
| Location scope | Owner may pass `location_id`; Manager's is implied and a mismatched value returns 404 |

### Response envelope

```json
{
  "data": { },
  "meta": { "total": 128, "page": 1, "per_page": 25, "pages": 6 }
}
```

---

## 2. Error Format

```json
{
  "error": {
    "code": "slot_taken",
    "message": "That time was just booked by someone else.",
    "details": { "suggested_slots": ["2026-08-15T16:00:00-05:00"] }
  }
}
```

| HTTP | Code | Meaning |
|---|---|---|
| 400 | `bad_request` | Malformed input |
| 401 | `unauthenticated` | No/expired session |
| 403 | `forbidden` | Authenticated but not permitted (role or location scope) |
| 403 | `owner_approval_required` | Manager attempted to approve a location-change request (BR-06) |
| 404 | `not_found` | Also returned instead of 403 for out-of-scope records, to avoid leaking existence |
| 409 | `slot_taken` | Exclusion constraint hit — expected, routine |
| 409 | `shift_conflict` | Overlapping published shift |
| 422 | `validation_failed` | Field errors in `details.fields` |
| 422 | `insufficient_therapists` | Two-therapist service, only one free (C12) |
| 422 | `no_suitable_room` | No room with enough client capacity, or no free room of a required exclusive type |
| 422 | `insufficient_balance` | Gift card redemption exceeds balance |
| 422 | `no_membership_credit` | Credit redemption with a zero balance |
| 422 | `membership_wrong_location` | Credit redeemed away from the membership's home location without an Owner/Manager override (BR-39a) |
| 422 | `credit_cap_reached` | Grant would exceed the 3-credit cap (BR-38) |
| 422 | `outside_booking_window` | Inside the cut-off, or beyond the 6-month horizon *(client channel, Release 2)* |
| 422 | `period_locked` | Edit attempted on a locked earnings period |
| 422 | `query_too_short` | Therapist name search below 2 characters (BR-13) *(Release 2)* |
| 422 | `payment_required` | Deposit or full payment not completed *(Release 2)* |
| 423 | `offboard_blocked` | Staff has future appointments |
| 429 | `rate_limited` | Public endpoints |

---

## 3. Authentication

### Staff (Owner, Manager, Staff)

| Method | Path | Notes |
|---|---|---|
| POST | `/session` | Login. `{email, password, otp_code?}`. Sets the staff cookie. |
| DELETE | `/session` | Logout |
| GET | `/me` | Current user, role, location scope, granted permissions |
| POST | `/password_resets` · PUT `/password_resets/:token` | Reset flow |
| POST | `/me/otp` | Enrol TOTP (required for Owner) |

`GET /me` returns the flags the console needs, including `can_edit_service_menu` for a Staff user
whom the Owner has granted menu access (FRS §2, §19.1).

### Client *(Release 2)*

No client authenticates in Release 1.

| Method | Path | Notes |
|---|---|---|
| POST | `/public/auth/request_code` | `{phone}` → sends a 6-digit SMS code. Rate-limited per phone and per IP. |
| POST | `/public/auth/verify_code` | `{phone, code}` → sets the **client** cookie (separate key and scope) |
| POST | `/public/auth/register` | `{first_name, last_name, phone, email, sms_consent, email_consent}` |
| DELETE | `/public/session` | Logout |
| GET | `/public/me` | Client profile, membership summary, gift card balances |

---

## 4. Organization

| Method | Path | Roles |
|---|---|---|
| GET | `/locations` | all authenticated (Owner sees 4, Manager sees 1) |
| PATCH | `/locations/:id` | **owner** — booking cut-off, horizon, fee and deposit percentages, hours |
| GET | `/locations/:id/business_hours` · PUT | all read · owner write |
| GET/POST/DELETE | `/locations/:id/closures` | owner, manager |
| GET | `/locations/:id/rooms` | all — includes `room_type`, `client_capacity` and `exclusive` |
| POST/PATCH | `/locations/:id/rooms/:room_id` | owner |
| GET/POST/DELETE | `/rooms/:id/blocks` | owner, manager — time-bounded room unavailability |

---

## 5. Catalogue

| Method | Path | Roles |
|---|---|---|
| GET | `/service_categories` | all |
| GET | `/services?active=true&location_id=&kind=` | all + **public** |
| POST/PATCH/DELETE | `/services/:id` | **owner**; staff only with `can_edit_service_menu` |
| POST | `/services/:id/activate` · `/deactivate` | owner — FRS §19.1, deactivate without deleting |
| GET | `/services/:id/variants` | all + **public** |
| POST/PATCH | `/service_variants/:id` | owner |
| GET | `/service_variants/:id/prices?location_id=` | owner |
| POST | `/service_variants/:id/prices` | owner — creates a new effective-dated row, never updates |

`GET /services?location_id=3` returns each variant with the **resolved price for today at that
location**, so no client ever implements price resolution.

```json
{
  "data": [{
    "id": 4, "name": "Deep Tissue / Sport / Swedish", "category": "massage", "kind": "standard",
    "variants": [
      { "id": 11, "duration_minutes": 60, "price_cents": 8000,
        "therapist_count": 1, "required_client_capacity": 1, "requires_room_type": null },
      { "id": 12, "duration_minutes": 90, "price_cents": 11500,
        "therapist_count": 1, "required_client_capacity": 1, "requires_room_type": null }
    ]
  }, {
    "id": 8, "name": "Couples massage", "category": "massage", "kind": "standard",
    "variants": [
      { "id": 31, "duration_minutes": 60, "price_cents": 16000,
        "therapist_count": 2, "required_client_capacity": 2, "requires_room_type": null }
    ]
  }, {
    "id": 22, "name": "Scalp massage", "category": "add_on", "kind": "add_on",
    "variants": [
      { "id": 77, "duration_minutes": 30, "price_cents": 3500,
        "therapist_count": 1, "required_client_capacity": 1, "requires_room_type": null }
    ]
  }]
}
```

`therapist_count`, `required_client_capacity` and `requires_room_type` are on every variant so the
booking UI can tell a couples massage from a single one without a second call. Room *matching* is
by capacity, not by type equality — see doc 03 §2.4.

---

## 6. Workforce

| Method | Path | Roles | Notes |
|---|---|---|---|
| GET | `/staff?location_id=&status=` | owner, manager | **manager gets no rate fields at all** |
| POST | `/staff` | **owner** | user + profile + location + qualifications + rate ladder |
| GET | `/staff/:id` | owner; manager (no rates); staff (self) | |
| PATCH | `/staff/:id` | owner | includes `can_edit_service_menu` |
| POST | `/staff/:id/offboard` | **owner** | 423 `offboard_blocked` with the conflicting appointment list |
| GET/PUT | `/staff/:id/qualifications` | owner | |
| GET | `/staff/:id/session_rates` | **owner**; staff (self, read-only) | full effective-dated ladder |
| POST | `/staff/:id/session_rates` | **owner** | `{rates: [{duration_minutes, rate_cents}], effective_from, note}` — writes six new rows |
| GET/POST | `/staff/:id/monthly_rate` | **owner** | managers only (BR-36) |

```jsonc
// POST /staff/7/session_rates — the six-rung ladder, FRS §4
{
  "effective_from": "2026-09-01",
  "note": "Annual review",
  "rates": [
    { "duration_minutes": 30,  "rate_cents": 2500 },
    { "duration_minutes": 45,  "rate_cents": 3500 },
    { "duration_minutes": 60,  "rate_cents": 4500 },
    { "duration_minutes": 75,  "rate_cents": 5500 },
    { "duration_minutes": 90,  "rate_cents": 6500 },
    { "duration_minutes": 120, "rate_cents": 8500 }
  ]
}
```

All six rungs must be supplied together. A partial ladder is 422 — a therapist with a gap in the
ladder is a therapist whose pay silently fails on some booking.

### Shifts and requests

| Method | Path | Roles |
|---|---|---|
| GET | `/shifts?location_id=&staff_id=&from=&to=&status=` | owner, manager; staff (own) |
| POST | `/shifts` | owner, manager — 409 `shift_conflict` on overlap |
| PATCH | `/shifts/:id` | owner, manager — 422 if it would orphan appointments (BR-07) |
| DELETE | `/shifts/:id` | owner, manager — same guard |
| POST | `/shifts/publish` | owner, manager — bulk `{shift_ids[]}` |
| GET/POST/DELETE | `/shifts/:id/breaks` | owner, manager |
| GET | `/shifts/day?location_id=&date=` | owner, manager — who is working, who is not (FRS §3, §15) |

| Method | Path | Roles |
|---|---|---|
| GET | `/staff_requests?kind=&status=&staff_id=` | owner, manager (own location); staff (own) |
| POST | `/staff_requests` | **staff** — `{kind: shift_change\|location_change, shift_id?, requested_payload, note}` |
| POST | `/staff_requests/:id/approve` | `shift_change`: owner, manager · **`location_change`: owner only** |
| POST | `/staff_requests/:id/reject` | same |
| POST | `/staff_requests/:id/withdraw` | staff (own) |

A Manager calling approve on a `location_change` gets **403 `owner_approval_required`** — a
distinct code, not a generic forbidden, because the console shows a specific message for it
(BR-06).

---

## 7. Scheduling — the core endpoints

### 7.1 Availability search

```http
GET /api/v1/availability
      ?location_id=3
      &service_variant_ids[]=11&service_variant_ids[]=77   # service + add-ons
      &date_from=2026-08-15
      &date_to=2026-08-21
      &requested_staff_profile_id=7        # optional
      &channel=client                      # applies cut-off + 6-month horizon
```

```json
{
  "data": {
    "location_id": 3,
    "timezone": "America/Chicago",
    "duration_minutes": 90,
    "buffer_minutes": 15,
    "therapists_required": 1,
    "required_client_capacity": 1,
    "days": [{
      "date": "2026-08-15",
      "slots": [{
        "start_at":       "2026-08-15T09:00:00-05:00",
        "service_end_at": "2026-08-15T10:30:00-05:00",
        "staff": [{ "id": 7, "display_name": "Anna" }, { "id": 9, "display_name": "Bek" }],
        "room_available_count": 3
      }]
    }]
  }
}
```

- `duration_minutes` is the **sum of all requested variants** — a 60-min massage plus a 30-min
  add-on is 90.
- Slots are on the location's 15-minute grid (C13).
- **Public callers** get the same shape **without** `room_available_count` and **without** the
  `staff` array, unless they named a therapist. Rate-limited by IP.

### 7.2 Next available time for a specific therapist (FRS §5)

```http
GET /api/v1/availability/next_for_therapist
      ?staff_profile_id=7&location_id=3&service_variant_ids[]=11&after=2026-08-15T15:30:00-05:00&limit=3
```

Returns that therapist's next times only. **It never returns a different therapist** — FRS §5 is
explicit that the system does not suggest alternatives.

### 7.3 Booking

| Method | Path | Roles |
|---|---|---|
| POST | `/appointments` | owner, manager · **not staff** (BR-14) |
| GET | `/appointments?location_id=&date=&staff_id=&room_id=&status=` | scoped |
| GET | `/appointments/:id` | scoped |
| PATCH | `/appointments/:id` | owner, manager — notes and internal fields only |
| POST | `/appointments/:id/items` · DELETE `/items/:item_id` | owner, manager — add-ons and enhancements before start |
| POST | `/appointments/:id/reschedule` | owner, manager |
| POST | `/appointments/:id/cancel` | owner, manager, client (own) — applies the 4-hour fee rule |
| POST | `/appointments/:id/transition` | `{to: checked_in\|in_progress\|completed\|no_show}` |
| GET | `/appointments/calendar?location_id=&date=` | day board: rooms × time, 09:00–22:00, one query |

```jsonc
// POST /appointments
{
  "location_id": 3,
  "items": [
    { "service_variant_id": 11 },          // 60-min deep tissue
    { "service_variant_id": 77 },          // 30-min scalp add-on
    { "service_variant_id": 91 }           // essential oil enhancement, 0 min
  ],
  "start_at": "2026-08-15T09:00:00-05:00",
  "client_id": 412,                        // or "client": {…} for "Add New Client" (FRS §5)
  "participant_client_ids": [],            // second client for a couples service
  "staff_profile_ids": [7],                // omit and the engine assigns; 2 ids for couples
  "requested_staff_profile_id": 7,         // triggers pending_approval (BR-15)
  "room_id": null,                         // optional — engine assigns
  "booking_channel": "phone",
  "client_note": "Prefers firm pressure, avoid lower back",
  "appointment_note": "",
  "hold_token": "abc123"                   // online flow only
}
```

Returns **201** with the appointment, or:
- **409 `slot_taken`** with `details.suggested_slots`,
- **422 `insufficient_therapists`** when a two-therapist service has only one free,
- **422 `no_suitable_room`** when no room has the capacity the service needs, or the service
  requires an exclusive room type (head spa) and none is free.

The response carries `status`, which is `pending_approval` when `requested_staff_profile_id` was
set, plus `deposit_due_cents` and `total_cents`.

### 7.4 Therapist-request approval (FRS §5)

| Method | Path | Roles |
|---|---|---|
| GET | `/approval_requests?status=pending&location_id=` | owner, manager — the queue, with `pending_for_minutes`, `auto_approves_at` and `past_review_target` (>15 min) on every row (BR-15a) |
| POST | `/approval_requests/:id/approve` | owner, manager — appointment → `scheduled`, notifies client |
| POST | `/approval_requests/:id/reject` | owner, manager — appointment → `cancelled`, **full refund**, notifies client |

### 7.5 Slot holds (online flow only) *(Release 2)*

| Method | Path |
|---|---|
| POST | `/public/slot_holds` → `{hold_token, expires_at}` (10 min TTL) |
| DELETE | `/public/slot_holds/:token` |

---

## 8. Clients

| Method | Path | Roles | Notes |
|---|---|---|---|
| GET | `/clients?q=&phone=` | owner, manager | `q` searches name / phone / email |
| POST | `/clients` | owner, manager | also used by "Add New Client" on the appointment screen |
| GET | `/clients/:id` | owner, manager | includes no-show and cancellation counters |
| PATCH | `/clients/:id` | owner, manager |
| POST | `/clients/:id/merge` | **owner** — `{into_client_id}` |
| GET | `/clients/:id/appointments` | owner, manager; staff (shared appts only) |
| GET | `/clients/:id/orders` | owner, manager |
| GET | `/clients/:id/gift_cards` | owner, manager — FRS §12, cards shown on the profile |
| GET | `/clients/:id/ratings` | owner, manager |
| GET | `/clients/:id/history_summary` | owner, manager | visits, spend, favourite service/therapist, no-shows, days since last visit |

### Preferences and care notes — separately routed, separately permissioned

| Method | Path | Roles |
|---|---|---|
| GET | `/clients/:id/preferences` | owner, manager; staff with an appointment for this client |
| PUT | `/clients/:id/preferences` | owner, manager, staff — writes a new version, never destroys |
| GET | `/clients/:id/preferences/versions` | owner, manager |
| GET | `/appointments/:id/care_notes` | owner, manager; staff on that appointment |
| POST | `/appointments/:id/care_notes` | **staff on that appointment** |
| POST | `/care_notes/:id/supersede` | staff (author) — creates a correcting note, never edits |

Every `GET` on these two groups writes an `audit_logs` row recording who read it (doc 04 §5).

### Ratings (FRS §11.2)

| Method | Path | Roles |
|---|---|---|
| POST | `/public/ratings/:token` | **public** — signed token from the SMS link, tied to the appointment and therapist. *Ships in Release 1: it needs a phone number, not an account* |
| POST | `/kiosk/ratings` | kiosk bundle — `{appointment_id}` selected on the in-location screen |
| GET | `/reports/ratings?from=&to=&location_id=&staff_id=` | owner |
| GET | `/reports/ratings/alerts?from=&to=` | owner, manager (own location) — ratings below the location threshold (BR-45a) |

```jsonc
// POST /public/ratings/:token
{ "score": 9, "feedback": "Great pressure", "improvement": "Warmer room",
  "would_recommend": true }
```

`score` must be 1–10. A second submission for the same appointment returns 422 (BR-45). A score
**below** `locations.low_rating_alert_below` (default 6, so 1–5) notifies the Owner **and** that
location's Manager on submission.

---

## 9. Sales & Payments

| Method | Path | Roles |
|---|---|---|
| POST | `/orders` | owner, manager — `{location_id, client_id?, appointment_id?}` |
| GET | `/orders/:id` | scoped |
| POST | `/orders/:id/line_items` · DELETE `/line_items/:lid` | owner, manager (open orders only) |
| POST | `/orders/:id/discounts` | **owner** |
| POST | `/orders/:id/payments` | owner, manager — `{method, amount_cents, reference}` → `processing: "recorded"` |
| POST | `/orders/:id/gift_card_redemptions` | owner, manager — `{code, amount_cents}` |
| POST | `/orders/:id/membership_credit` | owner, manager — applies one credit, charges any upgrade difference |
| POST | `/orders/:id/tips` | owner, manager — `{amount_cents, allocations?: [{staff_profile_id, amount_cents}]}` |
| POST | `/orders/:id/settle` | owner, manager — validates coverage (BR-22), closes the order |
| POST | `/payments/:id/void` | **owner** — `{reason}` (BR-23) |
| POST | `/orders/:id/refunds` | **owner** — `{amount_cents, reason}` |
| GET | `/orders/:id/receipt.pdf` | scoped |

An order can carry **multiple payments of different methods, plus gift card redemptions, plus a
membership credit**. `settle` enforces
`sum(captured payments) + sum(redemptions) + sum(credits) >= total_cents` and rejects overpayment;
the surplus must be entered as a tip.

`POST /orders/:id/tips` with no `allocations` splits evenly across the appointment's therapists
(BR-24). Supplying `allocations` lets a Manager override the split; the amounts must sum to
`amount_cents`.

### Gateway payments (online only) *(Release 2)*

Release 1 has no gateway. Fees are written as an open `Fee` order line and settled through
`POST /orders/:id/payments` like any other amount owed.

| Method | Path | Roles |
|---|---|---|
| POST | `/public/appointments/:id/payment_intent` | client — `{amount_choice: "deposit"\|"full"}` → `{client_secret, amount_cents}` |
| POST | `/public/setup_intent` | client — save a card for future fee charges; records policy consent |
| POST | `/webhooks/stripe` | **unauthenticated, signature-verified** — idempotent by event id |

The browser never advances local state. `payment_intent.succeeded` on the webhook is what moves an
appointment out of pending payment (ADR-11).

---

## 10. Gift Cards

| Method | Path | Roles |
|---|---|---|
| POST | `/gift_cards` | **owner, manager** — issue. `{code?, initial_value_cents, purchase_payment_method, buyer_*, recipient_*}` |
| GET | `/gift_cards?code=&buyer_client_id=&status=&sold_at_location_id=` | owner, manager |
| GET | `/gift_cards/:code` | owner, manager — balance, status, full ledger |
| GET | `/gift_cards/scan/:barcode` | owner, manager — barcode lookup (FRS §12) |
| POST | `/gift_cards/:code/redeem` | owner, manager — normally called via the order endpoint |
| POST | `/gift_cards/:id/adjust` | **owner only** — `{amount_cents, reason}`, audit-logged |
| POST | `/gift_cards/:id/void` | **owner** |
| GET | `/public/gift_cards/:code/balance` | **public** — balance only, rate-limited, no PII |
| POST | `/public/gift_cards` | **client** — buy a digital card online; Stripe-paid, code generated *(Release 2)* |
| GET | `/reports/gift_card_liability?as_of=&location_id=` | **owner** |

**Staff have no access to any of these** (BR-31, FRS §2, §12).

Redemption returns **422 `insufficient_balance`** with `details.available_cents` when short, so the
UI can prompt for a second method rather than failing the sale.

Every card response carries `sold_at_location_id` (liability attribution, BR-27) separately from
the redeeming location on each ledger entry — these must never be conflated in reporting.

---

## 11. Membership

| Method | Path | Roles |
|---|---|---|
| GET | `/memberships?status=&location_id=` | owner, manager |
| POST | `/memberships` | owner, manager, client — `{client_id, location_id, default_service_variant_id}`, $80/mo. `location_id` is the home location and cannot be changed by the member |
| GET | `/memberships/:id` | owner, manager; client (own) |
| PATCH | `/memberships/:id` | owner, manager, client (own) — change the chosen 60-min service |
| GET | `/memberships/:id/credits` | owner, manager; client (own) — the credit ledger |
| POST | `/memberships/:id/request_cancellation` | owner, manager, client (own) — applies the 15-day rule |
| POST | `/memberships/:id/adjust_credits` | **owner** — `{amount, reason}`, audit-logged |
| POST | `/memberships/:id/authorize_cross_location` | **owner, manager** — `{appointment_id, reason}`; records the approver on the credit transaction (BR-39a) |
| GET | `/reports/membership?from=&to=` | **owner** |

`POST /memberships/:id/request_cancellation` returns `cancellation_effective_at`. When the request
lands inside the 15-day window, that date is the **end of the following period**, and the response
says so explicitly so the client is not surprised by one more charge (BR-40).

```jsonc
// GET /memberships/42
{
  "data": {
    "id": 42, "status": "active", "price_cents": 8000,
    "location_id": 3, "location_name": "Luma",
    "credits_balance": 2, "credits_cap": 3,
    "default_service_variant_id": 11,
    "current_period_end": "2026-09-15T00:00:00-05:00",
    "cancellation_requested_at": null,
    "cancellation_effective_at": null
  }
}
```

**No membership renewal reminder and no cancellation-window reminder are sent** (FRS §22).

---

## 12. Earnings & Payout

| Method | Path | Roles |
|---|---|---|
| GET | `/earning_periods?kind=semi_monthly&year=` | **owner** |
| POST | `/earning_periods/:id/build` | **owner** — build statements from completed service lines |
| GET | `/earning_periods/:id/statements?location_id=` | **owner** |
| GET | `/earning_statements/:id` | **owner**; staff (own) |
| GET | `/earning_lines?staff_id=&from=&to=&appointment_id=` | **owner**; staff (own) — each line carries `duration_minutes`, `rate_cents` and `covers_item_ids` |
| POST | `/earning_statements/:id/adjustments` | **owner** — `{service_date, amount_cents, reason}` |
| POST | `/earning_lines` | **owner** — manual session/tip entry (FRS §4) |
| POST | `/earning_periods/:id/lock` | **owner** (BR-37) |
| GET | `/earning_statements/:id.pdf` | owner; staff (own) |
| GET | `/reports/staff_earnings?from=&to=&staff_id=&location_id=` | **owner**; staff (own) |
| GET | `/manager_payouts?month=` | **owner** — flat monthly (BR-36) |

**Manager has no access to any endpoint in this section.** This is the single hardest boundary in
the permission model (FRS §2).

```jsonc
// GET /reports/staff_earnings?from=2026-08-01&to=2026-08-15&staff_id=7
// The shape of the FRS §4 / §8 table, verbatim.
{
  "data": {
    "staff_profile_id": 7, "display_name": "Anna",
    "period": { "from": "2026-08-01", "to": "2026-08-15", "kind": "semi_monthly" },
    "sessions": [
      { "duration_minutes": 30,  "quantity": 12, "earnings_cents": 30000 },
      { "duration_minutes": 45,  "quantity": 0,  "earnings_cents": 0 },
      { "duration_minutes": 60,  "quantity": 34, "earnings_cents": 153000 },
      { "duration_minutes": 75,  "quantity": 2,  "earnings_cents": 11000 },
      { "duration_minutes": 90,  "quantity": 18, "earnings_cents": 117000 },
      { "duration_minutes": 120, "quantity": 5,  "earnings_cents": 42500 }
    ],
    "tips_cents": 48200,
    "adjustments_cents": 0,
    "total_cents": 401700
  }
}
```

`from`/`to` accept any date, week, month or custom range; `kind=semi_monthly` selects the standing
1st–15th and 16th–EOM periods.

> **How `quantity` counts (BR-33).** A row counts *sessions as paid*, not menu items sold. A
> 60-minute massage booked with a 30-minute add-on contributes **one unit to the 90-minute row**,
> because the total lands on a ladder rung and is paid as one 90-minute session. A 120-minute
> massage with a 30-minute add-on has no 150 rung, so it contributes one unit to the 120 row and
> one to the 30 row. `GET /earning_lines?appointment_id=` returns each line with its
> `covers_item_ids`, which is how a therapist querying their statement is shown what a combined
> line absorbed.

---

## 13. Reporting

All accept `from`, `to`, `location_id[]` and `format=json|xlsx|pdf`. Non-JSON returns **202
Accepted** with a job id and later a signed download URL.

| Path | Contents | Roles | FRS |
|---|---|---|---|
| `/reports/dashboard?location_id=&date=` | Appointments, completed, revenue, tips, staff working / not working, available rooms, gift cards sold and redeemed | owner; manager (own location, **no money fields**) | §15 |
| `/reports/daily_revenue` | Card, Cash, Zelle, Online, Other, Tips, Total | **owner** | §10 |
| `/reports/client_log?date=` | Time, client, therapist, service, length, price, tip, total paid, method | owner, manager | §9 |
| `/reports/staff_earnings` | §12 above | owner; staff (own) | §4, §8 |
| `/reports/gift_card_liability` | Outstanding balance by issue month and **selling** location | **owner** | §12 |
| `/reports/membership` | Active members, credits outstanding, at-cap, upgrades, pending cancellations | **owner** | §23 |
| `/reports/ratings` | Average and distribution per therapist, per location; recommend rate | **owner** | §11.2 |
| `/reports/utilization` | Room and therapist utilisation | **owner** | — |
| `/reports/no_shows` | No-show and late-cancel rates by location, therapist, weekday, channel; fees collected | **owner** | §21 |
| `/reports/client_retention` | New vs returning, frequency, lapsed, LTV | **owner** | §11 |

Owner-scoped reports accept multiple `location_id[]` values or none at all, which is how FRS §16's
"Owner-level reports can combine information from all four locations" is served.

The Manager's dashboard response is the same endpoint with money fields omitted at the serialiser
layer, not merely hidden in the UI.

---

## 14. Public & Client Endpoints *(Release 2)*

None of this ships in Release 1. Served only from the client bundle, aggressively rate-limited
(Rack::Attack):

```
POST /api/v1/public/auth/request_code
POST /api/v1/public/auth/verify_code
POST /api/v1/public/auth/register
GET  /api/v1/public/locations
GET  /api/v1/public/services?location_id=
GET  /api/v1/public/availability
GET  /api/v1/public/therapists/search?q=          # min 2 chars, max 5 results, no roster
POST /api/v1/public/slot_holds
POST /api/v1/public/appointments                  # authenticated client only
POST /api/v1/public/appointments/:id/payment_intent
GET  /api/v1/public/appointments                  # my bookings
POST /api/v1/public/appointments/:id/cancel
GET  /api/v1/public/gift_cards/:code/balance
POST /api/v1/public/gift_cards                    # buy a digital card
GET  /api/v1/public/memberships/mine
POST /api/v1/public/ratings/:token                # signed link from SMS
POST /api/v1/webhooks/stripe                      # signature-verified
```

- **Booking requires a client account** (FRS §5.1) — there is no guest booking flow.
- **`/public/therapists/search` is the only therapist endpoint on this surface**, and it cannot
  enumerate. `q` shorter than 2 characters returns **422 `query_too_short`** — never a full list
  (BR-13). Responses carry `id` and `display_name` (first name) only.
- Rate limits: 30 availability calls/min/IP, 5 booking attempts/min/IP, 10 auth-code requests/hour/
  phone, 20 therapist searches/min/session, 10 gift card lookups/hour/IP.
- Bot protection (Turnstile / reCAPTCHA) on `POST /public/auth/request_code` and
  `POST /public/appointments`.

---

## 15. Capabilities Deliberately Not Exposed

Recorded so each absence reads as a decision, not an omission:

| Not built | Why |
|---|---|
| Service packages / prepaid session bundles | Removed from scope entirely by FRS §26 — not deferred. Membership (§11) is the only recurring-entitlement product. |
| Health intake questionnaire, consent waiver | Not in FRS v7. The Client Preferences form (§8) is the only structured health-adjacent input. |
| Clinical SOAP notes | Not in FRS v7. `/appointments/:id/care_notes` carries the therapist's "avoid / attend to / consider" log instead — see doc 04 §5. |
| Recurring availability patterns | FRS §3 describes concrete shift records and a request-and-approve workflow, not weekly templates. Shifts are created directly; `/staff_requests` handles changes. |
| Time-off requests | Not in FRS v7 — an absence is handled by editing or removing the shift (FRS §3). |
| Hourly rates, timesheets, pay periods | Therapists are 1099 contractors paid per completed session (FRS §4, §18). `/staff/:id/session_rates` and `/earning_periods` replace the hourly model entirely. |
| Guest booking by signed email link | FRS §5.1 requires a client account for self-service booking. Owner and Manager book on behalf of account-less clients instead. |
| Therapist roster listing on the public surface | FRS §5.1 forbids it. `/public/therapists/search` cannot enumerate — see §14 and BR-13. |

## 16. Integrations Beyond v1

Stripe (payments, subscriptions) and Twilio (SMS) are in v1. Deliberately **not** in v1, recorded
as decisions: accounting export (QuickBooks), marketing platform, loyalty programme, Google/Yelp
review syndication from the rating flow, and card processing for in-salon checkout (which would
replace the existing terminal — see ADR-10).
