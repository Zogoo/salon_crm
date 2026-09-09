# Doc 02 §3.2. Three pieces of "when can this place actually be booked":
# per-weekday hours (which may be split), whole-day closures, and time-bounded
# unavailability for a single room.
class AddLocationHoursClosuresAndRoomBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :location_business_hours do |t|
      t.references :location, null: false, foreign_key: true
      t.integer :day_of_week, null: false          # 0 = Sunday
      t.time :opens_at, null: false
      t.time :closes_at, null: false
      t.timestamps
      # Several rows per day are allowed on purpose: split hours.
      t.index %i[location_id day_of_week]
    end

    create_table :location_closures do |t|
      t.references :location, null: false, foreign_key: true
      t.date :date, null: false
      t.string :reason
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.timestamps
      t.index %i[location_id date], unique: true
    end

    create_table :room_blocks do |t|
      t.references :room, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :reason
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.timestamps
      t.index %i[room_id starts_at]
    end
  end
end
