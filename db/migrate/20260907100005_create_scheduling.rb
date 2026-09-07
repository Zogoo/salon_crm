class CreateScheduling < ActiveRecord::Migration[8.1]
  ACTIVE = %w[pending_approval scheduled checked_in in_progress completed].freeze

  def change
    create_table :appointments do |t|
      t.string  :reference, null: false
      t.references :client, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :service_ends_at, null: false        # what the client is told
      t.datetime :ends_at, null: false                # service + buffer — BR-10 lives here
      t.string  :status, null: false, default: "scheduled"
      t.integer :total_price_cents, null: false, default: 0
      t.string  :booking_channel, null: false, default: "manager"
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.references :requested_staff_profile, foreign_key: { to_table: :staff_profiles }
      t.text    :client_note
      t.text    :appointment_note
      t.integer :fee_charged_cents, null: false, default: 0
      t.datetime :cancelled_at
      t.string  :cancellation_reason
      t.references :rescheduled_from, foreign_key: { to_table: :appointments }
      t.timestamps
    end
    add_index :appointments, :reference, unique: true
    # The two hot paths for the conflict check (doc 08 §2).
    add_index :appointments, %i[room_id status starts_at ends_at]
    add_index :appointments, %i[location_id status starts_at]
    add_index :appointments, %i[client_id starts_at]

    # Therapist conflicts are company-wide, so they are checked on this table.
    create_table :appointment_staff do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :staff_profile, null: false, foreign_key: true
      t.string   :role, null: false, default: "primary"
      # Denormalised from the parent so a conflict query never needs a join.
      t.datetime :starts_at, null: false
      t.datetime :ends_at,   null: false
      t.string   :status,    null: false
      t.timestamps
    end
    add_index :appointment_staff, %i[appointment_id staff_profile_id], unique: true
    add_index :appointment_staff, %i[staff_profile_id status starts_at ends_at],
              name: "idx_appt_staff_conflict"

    create_table :appointment_items do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :service_variant, null: false, foreign_key: true
      t.string  :kind, null: false                    # service | add_on | enhancement
      t.integer :duration_minutes, null: false, default: 0
      t.integer :price_cents, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :appointment_participants do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.integer :position, null: false, default: 1
      t.timestamps
    end
    add_index :appointment_participants, %i[appointment_id client_id], unique: true

    create_table :appointment_status_events do |t|
      t.references :appointment, null: false, foreign_key: true
      t.string   :from_status
      t.string   :to_status, null: false
      t.references :actor_user, foreign_key: { to_table: :users }
      t.datetime :occurred_at, null: false
      t.string   :reason
      t.timestamps
    end

    # FRS §5 — specific-therapist requests need Owner/Manager approval (BR-15).
    create_table :approval_requests do |t|
      t.references :appointment, null: false, foreign_key: true, index: { unique: true }
      t.references :requested_staff_profile, null: false, foreign_key: { to_table: :staff_profiles }
      t.string   :status, null: false, default: "pending"
      t.references :requested_by_user, foreign_key: { to_table: :users }
      t.references :reviewed_by_user, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text     :note
      t.timestamps
    end
    add_index :approval_requests, :status
  end
end
