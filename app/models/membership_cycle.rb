class MembershipCycle < ApplicationRecord
  belongs_to :membership
  belongs_to :order, optional: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
