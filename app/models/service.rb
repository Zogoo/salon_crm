class Service < ApplicationRecord
  KINDS = %w[standard add_on enhancement].freeze

  belongs_to :service_category
  has_many :service_variants, dependent: :destroy
  has_many :staff_qualifications, dependent: :destroy

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(active: true) }
  # Only these two consume therapist time and therefore pay (BR-33).
  scope :payable, -> { where(kind: %w[standard add_on]) }
end
