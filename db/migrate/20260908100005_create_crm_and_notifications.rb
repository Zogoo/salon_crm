class CreateCrmAndNotifications < ActiveRecord::Migration[8.1]
  def change
    # Doc 01 §3.10 / doc 04 §5. The therapist's "avoid / attend to / consider"
    # log. Deliberately NOT a clinical record — no intake, no consent, no SOAP —
    # but still body-related information about an identifiable person, so it is
    # encrypted, scoped, and append-only.
    create_table :care_notes do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :staff_profile, null: false, foreign_key: true
      t.text :body, null: false
      t.references :supersedes_note, foreign_key: { to_table: :care_notes }
      t.datetime :created_at, null: false           # no updated_at — never modified
    end
    add_index :care_notes, %i[appointment_id created_at]

    # FRS §11.2
    create_table :appointment_ratings do |t|
      t.references :appointment, null: false, foreign_key: true, index: { unique: true }
      t.references :staff_profile, null: false, foreign_key: true
      t.integer :score, null: false
      t.text    :feedback
      t.text    :improvement
      t.boolean :would_recommend
      t.string  :channel, null: false                # kiosk | sms_link
      t.datetime :submitted_at, null: false
      t.timestamps
    end
    add_index :appointment_ratings, %i[staff_profile_id submitted_at]
    add_check_constraint :appointment_ratings, "score BETWEEN 1 AND 10", name: "rating_score_range"

    # Signed, single-use token for the SMS rating link — no client account needed.
    add_column :appointments, :rating_token, :string
    add_index  :appointments, :rating_token, unique: true

    create_table :notifications do |t|
      t.string  :recipient_type, null: false          # Client | User
      t.bigint  :recipient_id, null: false
      t.string  :channel, null: false                 # email | sms
      t.string  :template_key, null: false
      t.text    :payload, null: false, default: "{}"
      t.datetime :scheduled_for
      t.datetime :sent_at
      t.string  :status, null: false, default: "pending"
      t.string  :provider_message_id
      t.text    :error
      t.references :appointment, foreign_key: true
      t.timestamps
    end
    add_index :notifications, %i[recipient_type recipient_id]
    add_index :notifications, %i[status scheduled_for]
    # Idempotency: a template fires once per appointment per channel.
    add_index :notifications, %i[appointment_id template_key channel],
              unique: true, name: "idx_notifications_once"

    create_table :audit_logs do |t|
      t.string  :auditable_type, null: false
      t.bigint  :auditable_id, null: false
      t.string  :action, null: false
      t.references :actor_user, foreign_key: { to_table: :users }
      t.string  :actor_role
      t.text    :changes_json, null: false, default: "{}"
      t.string  :ip_address
      t.datetime :occurred_at, null: false
    end
    add_index :audit_logs, %i[auditable_type auditable_id occurred_at]
    add_index :audit_logs, %i[actor_user_id occurred_at]
  end
end
