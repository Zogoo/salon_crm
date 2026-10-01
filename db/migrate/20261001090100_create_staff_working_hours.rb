# Addendum §8: each therapist's usual week. One row per weekday that has been
# set; a day with no row is "not set" and places no limit on booking.
class CreateStaffWorkingHours < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_working_hours do |t|
      t.references :staff_profile, null: false, foreign_key: true
      # 0 = Sunday … 6 = Saturday, the same numbering as Date#wday.
      t.integer :weekday, null: false
      t.boolean :off, null: false, default: false
      # Wall-clock "HH:MM" in the location's zone, like opening hours.
      t.string :starts_at
      t.string :ends_at
      t.timestamps
    end
    add_index :staff_working_hours, %i[staff_profile_id weekday], unique: true
  end
end
