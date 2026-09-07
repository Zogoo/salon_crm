class OrderDiscount < ApplicationRecord
  KINDS = %w[manual membership_upgrade_credit].freeze

  belongs_to :order
  belongs_to :applied_by_user, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
