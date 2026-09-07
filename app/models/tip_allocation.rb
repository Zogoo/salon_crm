class TipAllocation < ApplicationRecord
  belongs_to :order
  belongs_to :appointment, optional: true
  belongs_to :staff_profile

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
