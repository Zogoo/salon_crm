class ClientPreference < ApplicationRecord
  PRESSURES = %w[light medium firm].freeze

  belongs_to :client
  belongs_to :updated_by_user, class_name: "User", optional: true

  validates :pressure, inclusion: { in: PRESSURES }, allow_blank: true
end
