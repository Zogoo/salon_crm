# API Design

**Version:** 1.0 · `/api/v1` · JSON · session-cookie authenticated · same-origin

---

## 1. Conventions

| Aspect | Convention |
|---|---|
| Base path | `/api/v1` |
| Content type | `application/json` |
| Auth | httpOnly session cookie + `X-CSRF-Token` header on writes |
| Timestamps | ISO 8601 **with offset**: `2026-08-15T15:30:00-04:00` |
| Money | integer cents, field suffix `_cents` |
| IDs | numeric internally; public-facing objects also expose `reference` / `code` |
| Pagination | `?page=1&per_page=25`; response envelope carries `meta.total`, `meta.pages` |
| Filtering | explicit query params only, no generic query DSL |
| Errors | RFC 7807-ish body, see §2 |
| Idempotency | `Idempotency-Key` header honoured on `POST /appointments`, `/payments`, `/gift_cards` |

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
    "details": { "suggested_slots": ["2026-08-15T16:00:00-04:00"] }
  }
}
```

| HTTP | Code | Meaning |
|---|---|---|
| 400 | `bad_request` | Malformed input |
| 401 | `unauthenticated` | No/expired session |
| 403 | `forbidden` | Authenticated but not permitted (role or location scope) |
| 404 | `not_found` | Also returned instead of 403 for out-of-scope records, to avoid leaking existence |
| 409 | `slot_taken` | Exclusion constraint hit — expected, routine |
| 409 | `shift_conflict` | Overlapping published shift |
| 422 | `validation_failed` | Field errors in `details.fields` |
| 422 | `insufficient_balance` | Gift card / package redemption exceeds balance |
| 422 | `period_locked` | Edit attempted on a locked pay period |
| 423 | `offboard_blocked` | Staff has future appointments |
| 429 | `rate_limited` | Public booking endpoints |

---

## 3. Authentication

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v1/session` | Login. Body `{email, password, otp_code?}`. Sets cookie. |
| DELETE | `/api/v1/session` | Logout |
| GET | `/api/v1/me` | Current user, role, accessible locations, feature flags |
| POST | `/api/v1/password_resets` | Request reset email |
| PUT | `/api/v1/password_resets/:token` | Complete reset |
| POST | `/api/v1/me/otp` | Enrol TOTP (required for owner/manager) |

---

## 4. Organization

| Method | Path | Roles |
|---|---|---|
| GET | `/locations` | all authenticated (scoped) |
| POST/PATCH | `/locations/:id` | owner |
| GET | `/locations/:id/business_hours` | all |
| PUT | `/locations/:id/business_hours` | owner, manager |
| GET/POST | `/locations/:id/closures` | owner, manager |
| GET | `/locations/:id/rooms` | all |
| POST/PATCH | `/locations/:id/rooms/:room_id` | owner, manager |
| GET/POST/DELETE | `/rooms/:id/blocks` | owner, manager — time-bounded room unavailability |

---

## 5. Catalogue

| Method | Path | Roles |
|---|---|---|
| GET | `/service_categories` | all |
| GET | `/services?active=true&location_id=` | all + **public** |
| POST/PATCH | `/services/:id` | owner, manager |
| GET | `/services/:id/variants` | all + **public** |
| POST/PATCH | `/service_variants/:id` | owner, manager |
| GET | `/service_variants/:id/prices?location_id=` | owner, manager |
| POST | `/service_variants/:id/prices` | owner, manager — creates a new effective-dated row, never updates |

`GET /services?location_id=3` returns each variant with the **resolved price for today at that
location**, so the booking UI never has to implement price resolution.

```json
{
  "data": [{
    "id": 4, "name": "Deep Tissue", "category": "Therapeutic",
    "variants": [
      { "id": 11, "duration_minutes": 60, "buffer_minutes": 15, "price_cents": 12000 },
      { "id": 12, "duration_minutes": 90, "buffer_minutes": 15, "price_cents": 16500 }
    ]
  }]
}
```

---

## 6. Workforce

| Method | Path | Roles | Notes |
|---|---|---|---|
| GET | `/staff?location_id=&status=` | owner, manager, front_desk | front_desk gets no rate fields |
| POST | `/staff` | owner, manager | onboarding: user + profile + locations + qualifications |
| GET | `/staff/:id` | owner, manager; therapist (self) | |
| PATCH | `/staff/:id` | owner, manager | |
| POST | `/staff/:id/offboard` | owner, manager | 423 `offboard_blocked` with the conflicting appointment list |
| GET/PUT | `/staff/:id/locations` | owner, manager | |
| GET/PUT | `/staff/:id/qualifications` | owner, manager | |
| GET | `/staff/:id/rates` | owner, manager; therapist (self, read-only) | full effective-dated history |
| POST | `/staff/:id/rates` | owner, manager | `{hourly_rate_cents, effective_from, note}` — new row |

### Availability & shifts

| Method | Path | Roles |
|---|---|---|
| GET | `/availability_requests?staff_id=&status=&from=&to=` | owner, manager; therapist (self) |
| POST | `/availability_requests` | therapist |
| POST | `/availability_requests/:id/approve` | owner, manager — creates the Shift |
| POST | `/availability_requests/:id/reject` | owner, manager |
| GET/POST/PATCH/DELETE | `/availability_patterns` | therapist (own); manager |
| GET | `/shifts?location_id=&staff_id=&from=&to=&status=` | owner, manager, front_desk (read); therapist (own) |
| POST | `/shifts` | owner, manager — 409 `shift_conflict` on overlap |
| PATCH | `/shifts/:id` | owner, manager — 422 if it would orphan appointments |
| POST | `/shifts/publish` | owner, manager — bulk publish `{shift_ids[]}` |
| DELETE | `/shifts/:id` | owner, manager |
| GET/POST | `/time_off_requests` | therapist (own); manager (all) |
| POST | `/time_off_requests/:id/approve` \| `/reject` | owner, manager |

---

## 7. Scheduling — the core endpoints

### 7.1 Availability search

```http
GET /api/v1/availability
      ?location_id=3
      &service_variant_id=11
      &date_from=2026-08-15
      &date_to=2026-08-21
      &staff_profile_id=7        # optional
      &channel=online            # applies lead time + horizon
```

```json
{
  "data": {
    "location_id": 3,
    "timezone": "America/New_York",
    "service_variant_id": 11,
    "duration_minutes": 60,
    "buffer_minutes": 15,
    "days": [{
      "date": "2026-08-15",
      "slots": [{
        "start_at": "2026-08-15T09:00:00-04:00",
        "end_at":   "2026-08-15T10:00:00-04:00",
        "staff": [{ "id": 7, "display_name": "Anna" }, { "id": 9, "display_name": "Bek" }],
        "room_available_count": 3
      }]
    }]
  }
}
```

Public (unauthenticated) callers get the same shape **without** `room_available_count` and with
staff limited to `id` + `display_name`. Rate-limited by IP.

### 7.2 Booking

| Method | Path | Roles |
|---|---|---|
| POST | `/appointments` | owner, manager, front_desk, **public** (online channel) |
| GET | `/appointments?location_id=&date=&staff_id=&room_id=&status=` | scoped |
| GET | `/appointments/:id` | scoped |
| PATCH | `/appointments/:id` | owner, manager, front_desk — notes and internal fields only |
| POST | `/appointments/:id/reschedule` | owner, manager, front_desk |
| POST | `/appointments/:id/cancel` | owner, manager, front_desk, customer (own) |
| POST | `/appointments/:id/transition` | `{to: checked_in\|in_progress\|completed\|no_show}` |
| GET | `/appointments/calendar?location_id=&date=` | day board: rooms × time grid, one query |

```jsonc
// POST /appointments
{
  "location_id": 3,
  "service_variant_id": 11,
  "start_at": "2026-08-15T09:00:00-04:00",
  "customer_id": 412,              // or "customer": {…} to create inline
  "staff_profile_id": 7,           // optional — engine assigns if omitted
  "room_id": null,                 // optional — engine assigns if omitted
  "booking_channel": "phone",
  "customer_note": "Prefers firm pressure, left shoulder",
  "hold_token": "abc123"           // online flow only
}
```

Returns **201** with the appointment, or **409 `slot_taken`** with `details.suggested_slots`.

### 7.3 Slot holds (online flow only)

| Method | Path |
|---|---|
| POST | `/slot_holds` → `{hold_token, expires_at}` (10 min TTL) |
| DELETE | `/slot_holds/:token` |

---

## 8. Customers

| Method | Path | Roles | Notes |
|---|---|---|---|
| GET | `/customers?q=&phone=&location_id=` | owner, manager, front_desk | `q` searches name/phone/email |
| POST | `/customers` | owner, manager, front_desk, public |
| GET | `/customers/:id` | owner, manager, front_desk | **no health fields** in payload for front_desk |
| PATCH | `/customers/:id` | owner, manager, front_desk |
| POST | `/customers/:id/merge` | owner, manager — `{into_customer_id}` |
| GET | `/customers/:id/appointments` | scoped |
| GET | `/customers/:id/orders` | owner, manager, front_desk |
| GET/PUT | `/customers/:id/preferences` | owner, manager, front_desk |
| GET | `/customers/:id/history_summary` | owner, manager | visits, spend, favourite service/therapist, no-shows, days since last visit |

### Health data — separately routed and separately permissioned

| Method | Path | Roles |
|---|---|---|
| GET | `/customers/:id/intake_forms` | owner, manager; therapist with an appointment for this customer |
| POST | `/customers/:id/intake_forms` | front_desk (submit on behalf), public (self-serve link) |
| GET | `/appointments/:id/soap_note` | owner, manager; authoring therapist |
| POST | `/appointments/:id/soap_note` | therapist (own appointment) |
| POST | `/soap_notes/:id/supersede` | therapist (author) — creates a correcting note, never edits |

Every `GET` on these two groups writes an `audit_logs` row recording who read it.

---

## 9. Sales & Payments

| Method | Path | Roles |
|---|---|---|
| POST | `/orders` | owner, manager, front_desk — `{location_id, customer_id?, appointment_id?}` |
| GET | `/orders/:id` | scoped |
| POST | `/orders/:id/line_items` | front_desk+ — `{purchasable_type, purchasable_id, quantity}` |
| DELETE | `/orders/:id/line_items/:lid` | front_desk+ (open orders only) |
| POST | `/orders/:id/discounts` | manager+ (front_desk up to a configurable cap) |
| POST | `/orders/:id/payments` | front_desk+ — `{method, amount_cents, reference}` |
| POST | `/orders/:id/gift_card_redemptions` | front_desk+ — `{code, amount_cents}` |
| POST | `/orders/:id/settle` | front_desk+ — validates coverage (BR-15), closes the order |
| POST | `/payments/:id/void` | manager, owner — `{reason}` (BR-17) |
| GET | `/orders/:id/receipt.pdf` | scoped |

An order can carry **multiple payments of different methods plus gift card redemptions**. `settle`
enforces `sum(captured payments) + sum(redemptions) >= total_cents` and rejects overpayment.

---

## 10. Gift Cards

| Method | Path | Roles |
|---|---|---|
| POST | `/gift_cards` | front_desk+ — issue. `{card_type, initial_value_cents \| service_variant_id, purchaser_customer_id, recipient_*, expires_at}` |
| GET | `/gift_cards?code=&purchaser_customer_id=&status=` | front_desk+ |
| GET | `/gift_cards/:code` | front_desk+ — balance, status, full ledger |
| GET | `/gift_cards/:code/lookup` | **public** — balance only, rate-limited, no PII |
| POST | `/gift_cards/:code/redeem` | front_desk+ — normally called via the order endpoint |
| POST | `/gift_cards/:id/adjust` | **owner, manager only** — `{amount_cents, reason}`, audit-logged |
| POST | `/gift_cards/:id/void` | owner |
| GET | `/reports/gift_card_liability?as_of=` | owner, manager |

Redemption returns **422 `insufficient_balance`** with `details.available_cents` when short, so the
UI can prompt for a second payment method rather than failing the sale.

### Packages / memberships (phase 3)

| Method | Path |
|---|---|
| GET/POST/PATCH | `/package_templates` |
| POST | `/customers/:id/packages` (purchase) |
| GET | `/customers/:id/packages` |
| POST | `/customer_packages/:id/redeem` |

---

## 11. Payroll

| Method | Path | Roles |
|---|---|---|
| GET | `/pay_periods` | owner, manager |
| POST | `/pay_periods/:id/generate` | owner, manager — build timesheets from published shifts |
| GET | `/pay_periods/:id/timesheets?location_id=` | owner, manager |
| GET | `/timesheets/:id` | owner, manager; therapist (own) |
| POST | `/timesheets/:id/adjustments` | owner, manager — `{work_date, minutes, reason}` |
| POST | `/pay_periods/:id/lock` | **owner only** (BR-25) |
| GET | `/pay_periods/:id/statements` | owner, manager |
| GET | `/pay_statements/:id.pdf` | owner, manager; therapist (own) |
| GET | `/reports/salary_summary?from=&to=&location_id=` | owner, manager (own locations) |

Any write to a locked period returns **422 `period_locked`**.

---

## 12. Reporting

All accept `from`, `to`, `location_id[]`, and `format=json|xlsx|pdf`. Non-JSON formats return
**202 Accepted** with a job id and later a signed download URL.

| Path | Contents |
|---|---|
| `/reports/revenue` | By location, service, category, payment method, day/week/month. Service revenue and gift card liability strictly separated (BR-19). |
| `/reports/utilization` | Room and staff utilisation with the denominators from BR-28 |
| `/reports/staff_performance` | Appointments, hours, revenue generated, repeat-customer rate per therapist |
| `/reports/customer_retention` | New vs returning, frequency, lapsed list, LTV, no-show rate |
| `/reports/salary_summary` | Hours × effective rate per staff per period |
| `/reports/gift_card_liability` | Outstanding balance by issue month and location |
| `/reports/no_shows` | No-show and late-cancel rates by location, therapist, weekday, channel |

---

## 13. Public (Unauthenticated) Endpoints

Strictly limited, aggressively rate-limited (Rack::Attack), and served only from the public bundle:

```
GET  /api/v1/public/locations
GET  /api/v1/public/services?location_id=
GET  /api/v1/public/availability
POST /api/v1/public/slot_holds
POST /api/v1/public/appointments
GET  /api/v1/public/gift_cards/:code/lookup
POST /api/v1/public/customers/:token/intake_forms   # signed one-time link
GET  /api/v1/public/appointments/:token             # signed manage-my-booking link
POST /api/v1/public/appointments/:token/cancel
```

- No customer login required in v1 — access to an existing booking is via a **signed, expiring
  token** emailed in the confirmation. This avoids building a full customer account system while
  still allowing self-service cancellation.
- Rate limits: 30 availability calls/min/IP, 5 booking attempts/min/IP, 10 gift card lookups/hour/IP.
- Bot protection (Turnstile/reCAPTCHA) on `POST /public/appointments`.

---

## 14. Webhooks / Integrations (out of scope for v1)

Deliberately none. Recorded here so it is a decision, not an omission. Likely phase-4 candidates:
accounting export (QuickBooks), SMS provider, marketing platform, card gateway if payment
processing is later brought in-house.
