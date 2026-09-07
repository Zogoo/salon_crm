class FixNotificationUniqueness < ActiveRecord::Migration[8.1]
  # The idempotency key left the recipient out, so a notification that fans out
  # to several people — the low-rating alert goes to Owner *and* the location
  # Manager (BR-45a) — silently dropped everyone after the first.
  def change
    remove_index :notifications, name: "idx_notifications_once"
    add_index :notifications,
              %i[appointment_id template_key channel recipient_type recipient_id],
              unique: true, name: "idx_notifications_once"
  end
end
