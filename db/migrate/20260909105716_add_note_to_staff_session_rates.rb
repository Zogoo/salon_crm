class AddNoteToStaffSessionRates < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_session_rates, :note, :text
  end
end
