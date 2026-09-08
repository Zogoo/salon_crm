# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_08_120001) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "appointment_items", force: :cascade do |t|
    t.integer "appointment_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_minutes", default: 0, null: false
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.integer "service_variant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_appointment_items_on_appointment_id"
    t.index ["service_variant_id"], name: "index_appointment_items_on_service_variant_id"
  end

  create_table "appointment_participants", force: :cascade do |t|
    t.integer "appointment_id", null: false
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id", "client_id"], name: "index_appointment_participants_on_appointment_id_and_client_id", unique: true
    t.index ["appointment_id"], name: "index_appointment_participants_on_appointment_id"
    t.index ["client_id"], name: "index_appointment_participants_on_client_id"
  end

  create_table "appointment_ratings", force: :cascade do |t|
    t.integer "appointment_id", null: false
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.text "feedback"
    t.text "improvement"
    t.integer "score", null: false
    t.integer "staff_profile_id", null: false
    t.datetime "submitted_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "would_recommend"
    t.index ["appointment_id"], name: "index_appointment_ratings_on_appointment_id", unique: true
    t.index ["staff_profile_id", "submitted_at"], name: "index_appointment_ratings_on_staff_profile_id_and_submitted_at"
    t.index ["staff_profile_id"], name: "index_appointment_ratings_on_staff_profile_id"
    t.check_constraint "score BETWEEN 1 AND 10", name: "rating_score_range"
  end

  create_table "appointment_staff", force: :cascade do |t|
    t.integer "appointment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.string "role", default: "primary", null: false
    t.integer "staff_profile_id", null: false
    t.datetime "starts_at", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id", "staff_profile_id"], name: "index_appointment_staff_on_appointment_id_and_staff_profile_id", unique: true
    t.index ["appointment_id"], name: "index_appointment_staff_on_appointment_id"
    t.index ["staff_profile_id", "status", "starts_at", "ends_at"], name: "idx_appt_staff_conflict"
    t.index ["staff_profile_id"], name: "index_appointment_staff_on_staff_profile_id"
  end

  create_table "appointment_status_events", force: :cascade do |t|
    t.integer "actor_user_id"
    t.integer "appointment_id", null: false
    t.datetime "created_at", null: false
    t.string "from_status"
    t.datetime "occurred_at", null: false
    t.string "reason"
    t.string "to_status", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_user_id"], name: "index_appointment_status_events_on_actor_user_id"
    t.index ["appointment_id"], name: "index_appointment_status_events_on_appointment_id"
  end

  create_table "appointments", force: :cascade do |t|
    t.text "appointment_note"
    t.string "booking_channel", default: "manager", null: false
    t.string "cancellation_reason"
    t.datetime "cancelled_at"
    t.integer "client_id", null: false
    t.text "client_note"
    t.datetime "created_at", null: false
    t.integer "created_by_user_id"
    t.datetime "ends_at", null: false
    t.integer "fee_charged_cents", default: 0, null: false
    t.integer "location_id", null: false
    t.string "rating_token"
    t.string "reference", null: false
    t.integer "requested_staff_profile_id"
    t.integer "rescheduled_from_id"
    t.integer "room_id", null: false
    t.datetime "service_ends_at", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "scheduled", null: false
    t.integer "total_price_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "starts_at"], name: "index_appointments_on_client_id_and_starts_at"
    t.index ["client_id"], name: "index_appointments_on_client_id"
    t.index ["created_by_user_id"], name: "index_appointments_on_created_by_user_id"
    t.index ["location_id", "status", "starts_at"], name: "index_appointments_on_location_id_and_status_and_starts_at"
    t.index ["location_id"], name: "index_appointments_on_location_id"
    t.index ["rating_token"], name: "index_appointments_on_rating_token", unique: true
    t.index ["reference"], name: "index_appointments_on_reference", unique: true
    t.index ["requested_staff_profile_id"], name: "index_appointments_on_requested_staff_profile_id"
    t.index ["rescheduled_from_id"], name: "index_appointments_on_rescheduled_from_id"
    t.index ["room_id", "status", "starts_at", "ends_at"], name: "idx_on_room_id_status_starts_at_ends_at_23db34bcb3"
    t.index ["room_id"], name: "index_appointments_on_room_id"
  end

  create_table "approval_requests", force: :cascade do |t|
    t.integer "appointment_id", null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.integer "requested_by_user_id"
    t.integer "requested_staff_profile_id", null: false
    t.datetime "reviewed_at"
    t.integer "reviewed_by_user_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_approval_requests_on_appointment_id", unique: true
    t.index ["requested_by_user_id"], name: "index_approval_requests_on_requested_by_user_id"
    t.index ["requested_staff_profile_id"], name: "index_approval_requests_on_requested_staff_profile_id"
    t.index ["reviewed_by_user_id"], name: "index_approval_requests_on_reviewed_by_user_id"
    t.index ["status"], name: "index_approval_requests_on_status"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor_role"
    t.integer "actor_user_id"
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.text "changes_json"
    t.string "ip_address"
    t.datetime "occurred_at", null: false
    t.index ["actor_user_id", "occurred_at"], name: "index_audit_logs_on_actor_user_id_and_occurred_at"
    t.index ["actor_user_id"], name: "index_audit_logs_on_actor_user_id"
    t.index ["auditable_type", "auditable_id", "occurred_at"], name: "idx_on_auditable_type_auditable_id_occurred_at_79f0d04385"
  end

  create_table "care_notes", force: :cascade do |t|
    t.integer "appointment_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "staff_profile_id", null: false
    t.integer "supersedes_note_id"
    t.index ["appointment_id", "created_at"], name: "index_care_notes_on_appointment_id_and_created_at"
    t.index ["appointment_id"], name: "index_care_notes_on_appointment_id"
    t.index ["staff_profile_id"], name: "index_care_notes_on_staff_profile_id"
    t.index ["supersedes_note_id"], name: "index_care_notes_on_supersedes_note_id"
  end

  create_table "client_notes", force: :cascade do |t|
    t.text "body", null: false
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["client_id", "created_at"], name: "index_client_notes_on_client_id_and_created_at"
    t.index ["client_id"], name: "index_client_notes_on_client_id"
    t.index ["created_by_user_id"], name: "index_client_notes_on_created_by_user_id"
  end

  create_table "client_preference_versions", force: :cascade do |t|
    t.text "attention_areas"
    t.text "avoid_areas"
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.text "other_requests"
    t.string "pressure"
    t.datetime "superseded_at", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_user_id"
    t.index ["client_id"], name: "index_client_preference_versions_on_client_id"
    t.index ["updated_by_user_id"], name: "index_client_preference_versions_on_updated_by_user_id"
  end

  create_table "client_preferences", force: :cascade do |t|
    t.text "attention_areas"
    t.text "avoid_areas"
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.text "other_requests"
    t.string "pressure"
    t.datetime "updated_at", null: false
    t.integer "updated_by_user_id"
    t.index ["client_id"], name: "index_client_preferences_on_client_id", unique: true
    t.index ["updated_by_user_id"], name: "index_client_preferences_on_updated_by_user_id"
  end

  create_table "clients", force: :cascade do |t|
    t.integer "cancel_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "date_of_birth"
    t.datetime "discarded_at"
    t.string "email"
    t.string "first_name", null: false
    t.datetime "first_visit_at"
    t.string "last_name", null: false
    t.datetime "last_visit_at"
    t.integer "late_cancel_count", default: 0, null: false
    t.integer "merged_into_client_id"
    t.integer "no_show_count", default: 0, null: false
    t.string "phone", null: false
    t.integer "preferred_location_id"
    t.string "search_name", default: "", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["email"], name: "index_clients_on_email"
    t.index ["merged_into_client_id"], name: "index_clients_on_merged_into_client_id"
    t.index ["phone"], name: "index_clients_on_phone"
    t.index ["preferred_location_id"], name: "index_clients_on_preferred_location_id"
    t.index ["search_name"], name: "index_clients_on_search_name"
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "earning_adjustments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_user_id"
    t.integer "earning_statement_id", null: false
    t.string "reason", null: false
    t.date "service_date", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_earning_adjustments_on_created_by_user_id"
    t.index ["earning_statement_id"], name: "index_earning_adjustments_on_earning_statement_id"
  end

  create_table "earning_lines", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "appointment_id"
    t.text "covers_item_ids"
    t.datetime "created_at", null: false
    t.integer "created_by_user_id"
    t.integer "duration_minutes"
    t.integer "location_id", null: false
    t.text "note"
    t.integer "quantity", default: 1, null: false
    t.integer "rate_cents"
    t.date "service_date", null: false
    t.string "source", null: false
    t.integer "staff_profile_id", null: false
    t.integer "tip_allocation_id"
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_earning_lines_on_appointment_id"
    t.index ["created_by_user_id"], name: "index_earning_lines_on_created_by_user_id"
    t.index ["location_id", "service_date", "duration_minutes"], name: "idx_on_location_id_service_date_duration_minutes_f1040a8e8f"
    t.index ["location_id"], name: "index_earning_lines_on_location_id"
    t.index ["staff_profile_id", "service_date"], name: "index_earning_lines_on_staff_profile_id_and_service_date"
    t.index ["staff_profile_id"], name: "index_earning_lines_on_staff_profile_id"
    t.index ["tip_allocation_id"], name: "index_earning_lines_on_tip_allocation_id"
  end

  create_table "earning_periods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "ends_on", null: false
    t.string "kind", default: "semi_monthly", null: false
    t.datetime "locked_at"
    t.integer "locked_by_user_id"
    t.date "starts_on", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["locked_by_user_id"], name: "index_earning_periods_on_locked_by_user_id"
    t.index ["starts_on", "ends_on"], name: "index_earning_periods_on_starts_on_and_ends_on", unique: true
  end

  create_table "earning_statements", force: :cascade do |t|
    t.integer "adjustments_cents", default: 0, null: false
    t.integer "approved_by_user_id"
    t.datetime "created_at", null: false
    t.integer "earning_period_id", null: false
    t.datetime "generated_at", null: false
    t.integer "gross_amount_cents", default: 0, null: false
    t.integer "service_earnings_cents", default: 0, null: false
    t.integer "staff_profile_id", null: false
    t.integer "tips_cents", default: 0, null: false
    t.integer "total_sessions", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_user_id"], name: "index_earning_statements_on_approved_by_user_id"
    t.index ["earning_period_id", "staff_profile_id"], name: "idx_on_earning_period_id_staff_profile_id_b949c30c41", unique: true
    t.index ["earning_period_id"], name: "index_earning_statements_on_earning_period_id"
    t.index ["staff_profile_id"], name: "index_earning_statements_on_staff_profile_id"
  end

  create_table "gift_card_transactions", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "appointment_id"
    t.integer "balance_after_cents", null: false
    t.datetime "created_at", null: false
    t.integer "gift_card_id", null: false
    t.string "kind", null: false
    t.integer "location_id"
    t.text "note"
    t.datetime "occurred_at", null: false
    t.integer "order_id"
    t.integer "performed_by_user_id"
    t.integer "redeemed_by_client_id"
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_gift_card_transactions_on_appointment_id"
    t.index ["gift_card_id", "occurred_at"], name: "index_gift_card_transactions_on_gift_card_id_and_occurred_at"
    t.index ["gift_card_id"], name: "index_gift_card_transactions_on_gift_card_id"
    t.index ["location_id"], name: "index_gift_card_transactions_on_location_id"
    t.index ["order_id"], name: "index_gift_card_transactions_on_order_id"
    t.index ["performed_by_user_id"], name: "index_gift_card_transactions_on_performed_by_user_id"
    t.index ["redeemed_by_client_id"], name: "index_gift_card_transactions_on_redeemed_by_client_id"
  end

  create_table "gift_cards", force: :cascade do |t|
    t.integer "buyer_client_id"
    t.string "buyer_name"
    t.string "buyer_phone"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "current_balance_cents", default: 0, null: false
    t.datetime "expires_at", null: false
    t.integer "initial_value_cents", null: false
    t.string "origin", default: "physical", null: false
    t.string "purchase_payment_method", null: false
    t.integer "recipient_client_id"
    t.string "recipient_name"
    t.string "recipient_phone"
    t.datetime "sold_at", null: false
    t.integer "sold_at_location_id", null: false
    t.integer "sold_by_user_id"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_client_id"], name: "index_gift_cards_on_buyer_client_id"
    t.index ["code"], name: "index_gift_cards_on_code", unique: true
    t.index ["recipient_client_id"], name: "index_gift_cards_on_recipient_client_id"
    t.index ["sold_at_location_id", "sold_at"], name: "index_gift_cards_on_sold_at_location_id_and_sold_at"
    t.index ["sold_at_location_id"], name: "index_gift_cards_on_sold_at_location_id"
    t.index ["sold_by_user_id"], name: "index_gift_cards_on_sold_by_user_id"
    t.index ["status"], name: "index_gift_cards_on_status"
  end

  create_table "location_prices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.integer "location_id", null: false
    t.integer "price_cents", null: false
    t.integer "service_variant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "service_variant_id", "effective_from"], name: "idx_location_prices_lookup", unique: true
    t.index ["location_id"], name: "index_location_prices_on_location_id"
    t.index ["service_variant_id"], name: "index_location_prices_on_service_variant_id"
  end

  create_table "locations", force: :cascade do |t|
    t.integer "booking_cutoff_minutes", default: 60, null: false
    t.integer "booking_horizon_days", default: 183, null: false
    t.integer "buffer_minutes", default: 15, null: false
    t.integer "cancellation_window_hours", default: 4, null: false
    t.time "closes_at", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "deposit_percent", default: 20, null: false
    t.integer "gift_card_expiry_months", default: 12, null: false
    t.integer "late_cancel_fee_percent", default: 20, null: false
    t.integer "low_rating_alert_below", default: 6, null: false
    t.string "name", null: false
    t.integer "no_show_fee_percent", default: 20, null: false
    t.time "opens_at", null: false
    t.text "reminder_offsets_minutes", default: "[1440,120]"
    t.integer "slot_granularity_minutes", default: 15, null: false
    t.string "status", default: "active", null: false
    t.string "timezone", default: "America/Chicago", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_locations_on_code", unique: true
  end

  create_table "manager_payouts", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.date "month", null: false
    t.datetime "paid_at"
    t.integer "staff_profile_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_profile_id", "month"], name: "index_manager_payouts_on_staff_profile_id_and_month", unique: true
    t.index ["staff_profile_id"], name: "index_manager_payouts_on_staff_profile_id"
  end

  create_table "membership_credit_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "appointment_id"
    t.integer "balance_after", null: false
    t.datetime "created_at", null: false
    t.integer "cross_location_approved_by_user_id"
    t.string "kind", null: false
    t.integer "membership_cycle_id"
    t.integer "membership_id", null: false
    t.text "note"
    t.datetime "occurred_at", null: false
    t.integer "performed_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_membership_credit_transactions_on_appointment_id"
    t.index ["cross_location_approved_by_user_id"], name: "idx_on_cross_location_approved_by_user_id_7c2f9319aa"
    t.index ["membership_cycle_id"], name: "index_membership_credit_transactions_on_membership_cycle_id"
    t.index ["membership_id"], name: "index_membership_credit_transactions_on_membership_id"
    t.index ["performed_by_user_id"], name: "index_membership_credit_transactions_on_performed_by_user_id"
  end

  create_table "membership_cycles", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "charged_at"
    t.datetime "created_at", null: false
    t.boolean "credit_granted", default: false, null: false
    t.boolean "forfeited_to_cap", default: false, null: false
    t.integer "membership_id", null: false
    t.integer "order_id"
    t.datetime "period_end", null: false
    t.datetime "period_start", null: false
    t.string "status", default: "open", null: false
    t.string "stripe_invoice_id"
    t.datetime "updated_at", null: false
    t.index ["membership_id", "period_start"], name: "index_membership_cycles_on_membership_id_and_period_start", unique: true
    t.index ["membership_id"], name: "index_membership_cycles_on_membership_id"
    t.index ["order_id"], name: "index_membership_cycles_on_order_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "cancellation_effective_at"
    t.datetime "cancellation_requested_at"
    t.integer "client_id", null: false
    t.datetime "created_at", null: false
    t.integer "credits_balance", default: 0, null: false
    t.datetime "current_period_end", null: false
    t.datetime "current_period_start", null: false
    t.integer "default_service_variant_id"
    t.datetime "enrolled_at", null: false
    t.integer "location_id", null: false
    t.integer "price_cents", default: 8000, null: false
    t.string "status", default: "active", null: false
    t.string "stripe_subscription_id"
    t.datetime "updated_at", null: false
    t.index ["client_id", "status"], name: "index_memberships_on_client_id_and_status"
    t.index ["client_id"], name: "index_memberships_on_client_id"
    t.index ["current_period_end"], name: "index_memberships_on_current_period_end"
    t.index ["default_service_variant_id"], name: "index_memberships_on_default_service_variant_id"
    t.index ["location_id"], name: "index_memberships_on_location_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "appointment_id"
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.text "payload", default: "{}"
    t.string "provider_message_id"
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "scheduled_for"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.string "template_key", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id", "template_key", "channel", "recipient_type", "recipient_id"], name: "idx_notifications_once", unique: true
    t.index ["appointment_id"], name: "index_notifications_on_appointment_id"
    t.index ["recipient_type", "recipient_id"], name: "index_notifications_on_recipient_type_and_recipient_id"
    t.index ["status", "scheduled_for"], name: "index_notifications_on_status_and_scheduled_for"
  end

  create_table "order_discounts", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "applied_by_user_id"
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "order_id", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.index ["applied_by_user_id"], name: "index_order_discounts_on_applied_by_user_id"
    t.index ["order_id"], name: "index_order_discounts_on_order_id"
  end

  create_table "order_line_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.integer "line_total_cents", default: 0, null: false
    t.integer "order_id", null: false
    t.bigint "purchasable_id"
    t.string "purchasable_type"
    t.integer "quantity", default: 1, null: false
    t.string "revenue_category", null: false
    t.integer "staff_profile_id"
    t.integer "unit_price_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_line_items_on_order_id"
    t.index ["purchasable_type", "purchasable_id"], name: "index_order_line_items_on_purchasable_type_and_purchasable_id"
    t.index ["revenue_category"], name: "index_order_line_items_on_revenue_category"
    t.index ["staff_profile_id"], name: "index_order_line_items_on_staff_profile_id"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "appointment_id"
    t.integer "client_id"
    t.datetime "closed_at"
    t.integer "closed_by_user_id"
    t.datetime "created_at", null: false
    t.integer "discount_cents", default: 0, null: false
    t.string "kind", default: "service", null: false
    t.integer "location_id", null: false
    t.string "number", null: false
    t.integer "opened_by_user_id"
    t.string "status", default: "open", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "tip_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_orders_on_appointment_id"
    t.index ["client_id", "status"], name: "index_orders_on_client_id_and_status"
    t.index ["client_id"], name: "index_orders_on_client_id"
    t.index ["closed_by_user_id"], name: "index_orders_on_closed_by_user_id"
    t.index ["location_id", "status", "closed_at"], name: "index_orders_on_location_id_and_status_and_closed_at"
    t.index ["location_id"], name: "index_orders_on_location_id"
    t.index ["number"], name: "index_orders_on_number", unique: true
    t.index ["opened_by_user_id"], name: "index_orders_on_opened_by_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "method", null: false
    t.integer "order_id", null: false
    t.string "processing", default: "recorded", null: false
    t.datetime "received_at", null: false
    t.integer "received_by_user_id"
    t.string "reference"
    t.string "status", default: "captured", null: false
    t.datetime "updated_at", null: false
    t.string "void_reason"
    t.datetime "voided_at"
    t.integer "voided_by_user_id"
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["received_at", "method", "status"], name: "index_payments_on_received_at_and_method_and_status"
    t.index ["received_by_user_id"], name: "index_payments_on_received_by_user_id"
    t.index ["voided_by_user_id"], name: "index_payments_on_voided_by_user_id"
  end

  create_table "refunds", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "issued_at", null: false
    t.integer "issued_by_user_id"
    t.integer "order_id", null: false
    t.integer "payment_id"
    t.string "reason", null: false
    t.datetime "updated_at", null: false
    t.index ["issued_by_user_id"], name: "index_refunds_on_issued_by_user_id"
    t.index ["order_id"], name: "index_refunds_on_order_id"
    t.index ["payment_id"], name: "index_refunds_on_payment_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.integer "client_capacity", null: false
    t.datetime "created_at", null: false
    t.boolean "exclusive", default: false, null: false
    t.integer "location_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "room_type", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "name"], name: "index_rooms_on_location_id_and_name", unique: true
    t.index ["location_id", "status", "client_capacity"], name: "index_rooms_on_location_id_and_status_and_client_capacity"
    t.index ["location_id"], name: "index_rooms_on_location_id"
  end

  create_table "service_categories", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_service_categories_on_code", unique: true
  end

  create_table "service_variants", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "base_price_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "duration_minutes", null: false
    t.integer "required_client_capacity", default: 1, null: false
    t.string "requires_room_type"
    t.integer "service_id", null: false
    t.integer "therapist_count", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "duration_minutes"], name: "index_service_variants_on_service_id_and_duration_minutes", unique: true
    t.index ["service_id"], name: "index_service_variants_on_service_id"
  end

  create_table "services", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "kind", default: "standard", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "service_category_id", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "active"], name: "index_services_on_kind_and_active"
    t.index ["service_category_id"], name: "index_services_on_service_category_id"
  end

  create_table "shift_breaks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.string "reason"
    t.integer "shift_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id"], name: "index_shift_breaks_on_shift_id"
  end

  create_table "shifts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.integer "location_id", null: false
    t.text "notes"
    t.integer "staff_profile_id", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "published", null: false
    t.datetime "updated_at", null: false
    t.date "work_date", null: false
    t.index ["location_id", "work_date", "status"], name: "index_shifts_on_location_id_and_work_date_and_status"
    t.index ["location_id"], name: "index_shifts_on_location_id"
    t.index ["staff_profile_id", "starts_at", "ends_at"], name: "index_shifts_on_staff_profile_id_and_starts_at_and_ends_at"
    t.index ["staff_profile_id"], name: "index_shifts_on_staff_profile_id"
  end

  create_table "staff_monthly_rates", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_user_id"
    t.date "effective_from", null: false
    t.date "effective_to"
    t.text "note"
    t.integer "staff_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_staff_monthly_rates_on_created_by_user_id"
    t.index ["staff_profile_id", "effective_from"], name: "idx_on_staff_profile_id_effective_from_afc6e694fb", unique: true
    t.index ["staff_profile_id"], name: "index_staff_monthly_rates_on_staff_profile_id"
  end

  create_table "staff_profiles", force: :cascade do |t|
    t.boolean "can_edit_service_menu", default: false, null: false
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "employee_code", null: false
    t.string "engagement_type", default: "contractor_1099", null: false
    t.date "hire_date", null: false
    t.integer "location_id", null: false
    t.string "status", default: "active", null: false
    t.date "termination_date"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["employee_code"], name: "index_staff_profiles_on_employee_code", unique: true
    t.index ["location_id", "status"], name: "index_staff_profiles_on_location_id_and_status"
    t.index ["location_id"], name: "index_staff_profiles_on_location_id"
    t.index ["user_id"], name: "index_staff_profiles_on_user_id", unique: true
  end

  create_table "staff_qualifications", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "service_id", null: false
    t.integer "staff_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_staff_qualifications_on_service_id"
    t.index ["staff_profile_id", "service_id"], name: "index_staff_qualifications_on_staff_profile_id_and_service_id", unique: true
    t.index ["staff_profile_id"], name: "index_staff_qualifications_on_staff_profile_id"
  end

  create_table "staff_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.text "note"
    t.text "requested_payload", default: "{}"
    t.text "review_note"
    t.datetime "reviewed_at"
    t.integer "reviewed_by_user_id"
    t.string "reviewer_role"
    t.integer "shift_id"
    t.integer "staff_profile_id", null: false
    t.string "status", default: "submitted", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewed_by_user_id"], name: "index_staff_requests_on_reviewed_by_user_id"
    t.index ["shift_id"], name: "index_staff_requests_on_shift_id"
    t.index ["staff_profile_id"], name: "index_staff_requests_on_staff_profile_id"
    t.index ["status", "kind"], name: "index_staff_requests_on_status_and_kind"
  end

  create_table "staff_session_rates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_minutes", null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.integer "rate_cents", null: false
    t.integer "staff_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_profile_id", "duration_minutes", "effective_from"], name: "idx_session_rates_lookup", unique: true
    t.index ["staff_profile_id"], name: "index_staff_session_rates_on_staff_profile_id"
  end

  create_table "tip_allocations", force: :cascade do |t|
    t.string "allocated_by", default: "system_even_split", null: false
    t.integer "amount_cents", null: false
    t.integer "appointment_id"
    t.datetime "created_at", null: false
    t.integer "order_id", null: false
    t.integer "staff_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_tip_allocations_on_appointment_id"
    t.index ["order_id"], name: "index_tip_allocations_on_order_id"
    t.index ["staff_profile_id", "created_at"], name: "index_tip_allocations_on_staff_profile_id_and_created_at"
    t.index ["staff_profile_id"], name: "index_tip_allocations_on_staff_profile_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "location_id"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "phone"
    t.string "role", default: "staff", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["location_id"], name: "index_users_on_location_id"
    t.index ["role"], name: "index_users_on_role"
    t.index ["status"], name: "index_users_on_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appointment_items", "appointments"
  add_foreign_key "appointment_items", "service_variants"
  add_foreign_key "appointment_participants", "appointments"
  add_foreign_key "appointment_participants", "clients"
  add_foreign_key "appointment_ratings", "appointments"
  add_foreign_key "appointment_ratings", "staff_profiles"
  add_foreign_key "appointment_staff", "appointments"
  add_foreign_key "appointment_staff", "staff_profiles"
  add_foreign_key "appointment_status_events", "appointments"
  add_foreign_key "appointment_status_events", "users", column: "actor_user_id"
  add_foreign_key "appointments", "appointments", column: "rescheduled_from_id"
  add_foreign_key "appointments", "clients"
  add_foreign_key "appointments", "locations"
  add_foreign_key "appointments", "rooms"
  add_foreign_key "appointments", "staff_profiles", column: "requested_staff_profile_id"
  add_foreign_key "appointments", "users", column: "created_by_user_id"
  add_foreign_key "approval_requests", "appointments"
  add_foreign_key "approval_requests", "staff_profiles", column: "requested_staff_profile_id"
  add_foreign_key "approval_requests", "users", column: "requested_by_user_id"
  add_foreign_key "approval_requests", "users", column: "reviewed_by_user_id"
  add_foreign_key "audit_logs", "users", column: "actor_user_id"
  add_foreign_key "care_notes", "appointments"
  add_foreign_key "care_notes", "care_notes", column: "supersedes_note_id"
  add_foreign_key "care_notes", "staff_profiles"
  add_foreign_key "client_notes", "clients"
  add_foreign_key "client_notes", "users", column: "created_by_user_id"
  add_foreign_key "client_preference_versions", "clients"
  add_foreign_key "client_preference_versions", "users", column: "updated_by_user_id"
  add_foreign_key "client_preferences", "clients"
  add_foreign_key "client_preferences", "users", column: "updated_by_user_id"
  add_foreign_key "clients", "clients", column: "merged_into_client_id"
  add_foreign_key "clients", "locations", column: "preferred_location_id"
  add_foreign_key "clients", "users"
  add_foreign_key "earning_adjustments", "earning_statements"
  add_foreign_key "earning_adjustments", "users", column: "created_by_user_id"
  add_foreign_key "earning_lines", "appointments"
  add_foreign_key "earning_lines", "locations"
  add_foreign_key "earning_lines", "staff_profiles"
  add_foreign_key "earning_lines", "tip_allocations"
  add_foreign_key "earning_lines", "users", column: "created_by_user_id"
  add_foreign_key "earning_periods", "users", column: "locked_by_user_id"
  add_foreign_key "earning_statements", "earning_periods"
  add_foreign_key "earning_statements", "staff_profiles"
  add_foreign_key "earning_statements", "users", column: "approved_by_user_id"
  add_foreign_key "gift_card_transactions", "appointments"
  add_foreign_key "gift_card_transactions", "clients", column: "redeemed_by_client_id"
  add_foreign_key "gift_card_transactions", "gift_cards"
  add_foreign_key "gift_card_transactions", "locations"
  add_foreign_key "gift_card_transactions", "orders"
  add_foreign_key "gift_card_transactions", "users", column: "performed_by_user_id"
  add_foreign_key "gift_cards", "clients", column: "buyer_client_id"
  add_foreign_key "gift_cards", "clients", column: "recipient_client_id"
  add_foreign_key "gift_cards", "locations", column: "sold_at_location_id"
  add_foreign_key "gift_cards", "users", column: "sold_by_user_id"
  add_foreign_key "location_prices", "locations"
  add_foreign_key "location_prices", "service_variants"
  add_foreign_key "manager_payouts", "staff_profiles"
  add_foreign_key "membership_credit_transactions", "appointments"
  add_foreign_key "membership_credit_transactions", "membership_cycles"
  add_foreign_key "membership_credit_transactions", "memberships"
  add_foreign_key "membership_credit_transactions", "users", column: "cross_location_approved_by_user_id"
  add_foreign_key "membership_credit_transactions", "users", column: "performed_by_user_id"
  add_foreign_key "membership_cycles", "memberships"
  add_foreign_key "membership_cycles", "orders"
  add_foreign_key "memberships", "clients"
  add_foreign_key "memberships", "locations"
  add_foreign_key "memberships", "service_variants", column: "default_service_variant_id"
  add_foreign_key "notes", "users"
  add_foreign_key "notifications", "appointments"
  add_foreign_key "order_discounts", "orders"
  add_foreign_key "order_discounts", "users", column: "applied_by_user_id"
  add_foreign_key "order_line_items", "orders"
  add_foreign_key "order_line_items", "staff_profiles"
  add_foreign_key "orders", "appointments"
  add_foreign_key "orders", "clients"
  add_foreign_key "orders", "locations"
  add_foreign_key "orders", "users", column: "closed_by_user_id"
  add_foreign_key "orders", "users", column: "opened_by_user_id"
  add_foreign_key "payments", "orders"
  add_foreign_key "payments", "users", column: "received_by_user_id"
  add_foreign_key "payments", "users", column: "voided_by_user_id"
  add_foreign_key "refunds", "orders"
  add_foreign_key "refunds", "payments"
  add_foreign_key "refunds", "users", column: "issued_by_user_id"
  add_foreign_key "rooms", "locations"
  add_foreign_key "service_variants", "services"
  add_foreign_key "services", "service_categories"
  add_foreign_key "shift_breaks", "shifts"
  add_foreign_key "shifts", "locations"
  add_foreign_key "shifts", "staff_profiles"
  add_foreign_key "staff_monthly_rates", "staff_profiles"
  add_foreign_key "staff_monthly_rates", "users", column: "created_by_user_id"
  add_foreign_key "staff_profiles", "locations"
  add_foreign_key "staff_profiles", "users"
  add_foreign_key "staff_qualifications", "services"
  add_foreign_key "staff_qualifications", "staff_profiles"
  add_foreign_key "staff_requests", "shifts"
  add_foreign_key "staff_requests", "staff_profiles"
  add_foreign_key "staff_requests", "users", column: "reviewed_by_user_id"
  add_foreign_key "staff_session_rates", "staff_profiles"
  add_foreign_key "tip_allocations", "appointments"
  add_foreign_key "tip_allocations", "orders"
  add_foreign_key "tip_allocations", "staff_profiles"
  add_foreign_key "users", "locations"
end
