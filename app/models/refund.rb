class Refund < ApplicationRecord
  REASONS = %w[fee_free_cancellation owner_discretion error].freeze

  belongs_to :order
  belongs_to :payment, optional: true
  belongs_to :issued_by_user, class_name: "User", optional: true

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :reason, inclusion: { in: REASONS }
end
