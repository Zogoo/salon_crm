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

ActiveRecord::Schema[8.1].define(version: 2026_09_07_100005) do
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
    t.integer "slot_granularity_minutes", default: 15, null: false
    t.string "status", default: "active", null: false
    t.string "timezone", default: "America/Chicago", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_locations_on_code", unique: true
  end

  create_table "notes", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_notes_on_user_id"
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
    t.text "requested_payload", default: "{}", null: false
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

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "location_id"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "role", default: "staff", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["location_id"], name: "index_users_on_location_id"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appointment_items", "appointments"
  add_foreign_key "appointment_items", "service_variants"
  add_foreign_key "appointment_participants", "appointments"
  add_foreign_key "appointment_participants", "clients"
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
  add_foreign_key "client_preference_versions", "clients"
  add_foreign_key "client_preference_versions", "users", column: "updated_by_user_id"
  add_foreign_key "client_preferences", "clients"
  add_foreign_key "client_preferences", "users", column: "updated_by_user_id"
  add_foreign_key "clients", "clients", column: "merged_into_client_id"
  add_foreign_key "clients", "locations", column: "preferred_location_id"
  add_foreign_key "clients", "users"
  add_foreign_key "location_prices", "locations"
  add_foreign_key "location_prices", "service_variants"
  add_foreign_key "notes", "users"
  add_foreign_key "rooms", "locations"
  add_foreign_key "service_variants", "services"
  add_foreign_key "services", "service_categories"
  add_foreign_key "shift_breaks", "shifts"
  add_foreign_key "shifts", "locations"
  add_foreign_key "shifts", "staff_profiles"
  add_foreign_key "staff_profiles", "locations"
  add_foreign_key "staff_profiles", "users"
  add_foreign_key "staff_qualifications", "services"
  add_foreign_key "staff_qualifications", "staff_profiles"
  add_foreign_key "staff_requests", "shifts"
  add_foreign_key "staff_requests", "staff_profiles"
  add_foreign_key "staff_requests", "users", column: "reviewed_by_user_id"
  add_foreign_key "staff_session_rates", "staff_profiles"
  add_foreign_key "users", "locations"
end
