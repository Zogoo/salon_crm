class CreateClients < ActiveRecord::Migration[8.1]
  def change
    # BR-42: clients are company-wide across all four locations.
    create_table :clients do |t|
      t.references :user, foreign_key: true          # only if they hold a portal account (Release 2)
      t.string  :first_name, null: false
      t.string  :last_name,  null: false
      t.string  :phone, null: false                  # E.164, primary search key
      t.string  :email
      t.date    :date_of_birth
      t.references :preferred_location, foreign_key: { to_table: :locations }
      t.integer :no_show_count,     null: false, default: 0
      t.integer :late_cancel_count, null: false, default: 0
      t.integer :cancel_count,      null: false, default: 0
      t.datetime :first_visit_at
      t.datetime :last_visit_at
      t.string  :status, null: false, default: "active"
      t.references :merged_into_client, foreign_key: { to_table: :clients }
      t.datetime :discarded_at
      # No pg_trgm on SQLite (doc 08 §2): name search is LIKE over this lowercased column.
      t.string  :search_name, null: false, default: ""
      t.timestamps
    end
    add_index :clients, :phone
    add_index :clients, :email
    add_index :clients, :search_name

    # FRS §11.1 — the "Form" on the New Appointment screen.
    create_table :client_preferences do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.text   :attention_areas
      t.text   :avoid_areas
      t.string :pressure                              # light | medium | firm
      t.text   :other_requests
      t.references :updated_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :client_preference_versions do |t|
      t.references :client, null: false, foreign_key: true
      t.text   :attention_areas
      t.text   :avoid_areas
      t.string :pressure
      t.text   :other_requests
      t.references :updated_by_user, foreign_key: { to_table: :users }
      t.datetime :superseded_at, null: false
      t.timestamps
    end
  end
end
