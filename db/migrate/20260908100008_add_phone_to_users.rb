class AddPhoneToUsers < ActiveRecord::Migration[8.1]
  # Doc 02 §3.1. Owner and Manager receive the low-rating alert by SMS as well
  # as email (doc 04 §7), so a staff user needs a phone number too.
  def change
    add_column :users, :phone, :string
  end
end
