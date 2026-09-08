class AddStatusToUsers < ActiveRecord::Migration[8.1]
  # Doc 02 §3.1 and BR-02: offboarding disables the login. Without this column
  # a terminated therapist kept working access to their own schedule, earnings
  # and the care notes of clients they had seen.
  def change
    add_column :users, :status, :string, null: false, default: "active"
    add_index :users, :status
  end
end
