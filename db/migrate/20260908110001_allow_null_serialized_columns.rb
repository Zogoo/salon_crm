class AllowNullSerializedColumns < ActiveRecord::Migration[8.1]
  # Rails writes NULL for a serialized empty Array or Hash — it treats the empty
  # value as the type's default and skips the dump. A NOT NULL column therefore
  # rejects every legitimately-empty value:
  #
  #   * a notification with nothing to interpolate
  #   * a staff request carrying no payload
  #   * a location that wants no reminders
  #
  # This already broke two features before it was understood (tip earning lines
  # and care-note read logging). Reads coerce NULL back to the empty value, so
  # nothing downstream changes.
  COLUMNS = {
    notifications: { payload: "{}" },
    staff_requests: { requested_payload: "{}" },
    locations: { reminder_offsets_minutes: "[1440,120]" }
  }.freeze

  def up
    COLUMNS.each do |table, columns|
      columns.each_key do |column|
        change_column_null table, column, true
      end
    end
  end

  def down
    COLUMNS.each do |table, columns|
      columns.each do |column, default|
        execute "UPDATE #{table} SET #{column} = '#{default}' WHERE #{column} IS NULL"
        change_column_null table, column, false
      end
    end
  end
end
