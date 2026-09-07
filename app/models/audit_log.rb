require "json"

class AuditLog < ApplicationRecord
  self.record_timestamps = false

  belongs_to :actor_user, class_name: "User", optional: true
  serialize :changes_json, coder: JSON, type: Hash

  def self.record!(auditable:, action:, actor: nil, changes: {}, ip: nil)
    create!(
      auditable_type: auditable.class.name, auditable_id: auditable.id,
      action:, actor_user: actor, actor_role: actor&.role,
      changes_json: changes, ip_address: ip, occurred_at: Time.current
    )
  end
end
