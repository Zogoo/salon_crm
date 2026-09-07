class ClientPreference < ApplicationRecord
  PRESSURES = %w[light medium firm].freeze

  belongs_to :client
  belongs_to :updated_by_user, class_name: "User", optional: true

  # Body-related information about an identifiable person (doc 04 §5).
  encrypts :attention_areas
  encrypts :avoid_areas
  encrypts :other_requests

  validates :pressure, inclusion: { in: PRESSURES }, allow_blank: true
end
