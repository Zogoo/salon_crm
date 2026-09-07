class CreateWorkforce < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :location, null: false, foreign_key: true
      t.string  :employee_code, null: false
      t.string  :display_name, null: false
      t.string  :engagement_type, null: false, default: "contractor_1099"
      t.date    :hire_date, null: false
      t.date    :termination_date
      t.string  :status, null: false, default: "active"
      t.boolean :can_edit_service_menu, null: false, default: false
      t.timestamps
    end
    add_index :staff_profiles, :employee_code, unique: true
    add_index :staff_profiles, %i[location_id status]

    create_table :staff_qualifications do |t|
      t.references :staff_profile, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :staff_qualifications, %i[staff_profile_id service_id], unique: true

    # BR-32/BR-35: the six-rung ladder, effective-dated, never edited in place.
    create_table :staff_session_rates do |t|
      t.references :staff_profile, null: false, foreign_key: true
      t.integer :duration_minutes, null: false
      t.integer :rate_cents, null: false
      t.date    :effective_from, null: false
      t.date    :effective_to
      t.timestamps
    end
    add_index :staff_session_rates, %i[staff_profile_id duration_minutes effective_from],
              unique: true, name: "idx_session_rates_lookup"

    create_table :shifts do |t|
      t.references :staff_profile, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.date     :work_date, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at,   null: false
      t.string   :status, null: false, default: "published"
      t.text     :notes
      t.timestamps
    end
    add_index :shifts, %i[staff_profile_id starts_at ends_at]
    add_index :shifts, %i[location_id work_date status]

    create_table :shift_breaks do |t|
      t.references :shift, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at,   null: false
      t.string   :reason
      t.timestamps
    end

    # BR-05/BR-06: staff never self-edit; location changes are Owner-only.
    create_table :staff_requests do |t|
      t.references :staff_profile, null: false, foreign_key: true
      t.references :shift, foreign_key: true
      t.string   :kind, null: false                  # shift_change | location_change
      t.text     :requested_payload, null: false, default: "{}"
      t.string   :status, null: false, default: "submitted"
      t.references :reviewed_by_user, foreign_key: { to_table: :users }
      t.string   :reviewer_role
      t.datetime :reviewed_at
      t.text     :note
      t.text     :review_note
      t.timestamps
    end
    add_index :staff_requests, %i[status kind]
  end
end
