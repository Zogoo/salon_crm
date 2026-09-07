require "json"

class Notification < ApplicationRecord
  CHANNELS = %w[email sms].freeze

  belongs_to :appointment, optional: true

  serialize :payload, coder: JSON, type: Hash

  validates :channel, inclusion: { in: CHANNELS }
  validates :template_key, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :due, ->(now = Time.current) { pending.where("scheduled_for IS NULL OR scheduled_for <= ?", now) }

  def recipient = recipient_type.constantize.find_by(id: recipient_id)
end
