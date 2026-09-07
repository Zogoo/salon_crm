class AddReminderOffsetsToLocations < ActiveRecord::Migration[8.1]
  def change
    # FRS §22 / OQ-05: two reminders, 24 h and 2 h before the start.
    # SQLite has no array type, so this is a serialised JSON list rather than
    # the integer[] the Postgres design assumed.
    add_column :locations, :reminder_offsets_minutes, :text, null: false, default: "[1440,120]"
  end
end
