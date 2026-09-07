class CreateOrganization < ActiveRecord::Migration[8.1]
  def change
    create_table :locations do |t|
      t.string  :name, null: false
      t.string  :code, null: false
      t.string  :timezone, null: false, default: "America/Chicago"
      t.time    :opens_at,  null: false
      t.time    :closes_at, null: false
      t.integer :slot_granularity_minutes, null: false, default: 15
      t.integer :buffer_minutes,           null: false, default: 15
      t.integer :booking_horizon_days,     null: false, default: 183
      t.integer :booking_cutoff_minutes,   null: false, default: 60
      t.integer :cancellation_window_hours, null: false, default: 4
      t.integer :no_show_fee_percent,      null: false, default: 20
      t.integer :late_cancel_fee_percent,  null: false, default: 20
      t.integer :deposit_percent,          null: false, default: 20
      t.integer :low_rating_alert_below,   null: false, default: 6
      t.integer :gift_card_expiry_months,  null: false, default: 12
      t.string  :status, null: false, default: "active"
      t.timestamps
    end
    add_index :locations, :code, unique: true

    create_table :rooms do |t|
      t.references :location, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :room_type, null: false           # single | couple | three_table | head_spa
      t.integer :client_capacity, null: false
      t.boolean :exclusive, null: false, default: false
      t.string  :status, null: false, default: "active"
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :rooms, %i[location_id name], unique: true
    add_index :rooms, %i[location_id status client_capacity]

    # BR-02 roles; manager is pinned to exactly one location.
    add_column :users, :role, :string, null: false, default: "staff"
    add_reference :users, :location, foreign_key: true, null: true
    add_index :users, :role
  end
end
