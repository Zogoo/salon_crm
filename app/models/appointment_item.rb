class AppointmentItem < ApplicationRecord
  KINDS = %w[service add_on enhancement].freeze

  belongs_to :appointment
  belongs_to :service_variant

  validates :kind, inclusion: { in: KINDS }

  scope :payable, -> { where(kind: %w[service add_on]) }
end
