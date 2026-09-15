class AddStaffAssignmentConfirmedToAppointments < ActiveRecord::Migration[8.1]
  def change
    add_column :appointments, :staff_assignment_confirmed, :boolean, null: false, default: true
  end
end
