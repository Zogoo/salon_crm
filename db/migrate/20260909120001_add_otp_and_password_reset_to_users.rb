class AddOtpAndPasswordResetToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      # TOTP enrolment (doc 05 §3). The secret is the second factor itself, so
      # it is never returned once enrolment is confirmed.
      t.string   :otp_secret
      t.datetime :otp_enabled_at
      # Single-use, expiring reset token. Stored as a digest so a leaked
      # database row cannot be replayed against the reset endpoint.
      t.string   :password_reset_token_digest
      t.datetime :password_reset_sent_at
    end
    add_index :users, :password_reset_token_digest, unique: true
  end
end
