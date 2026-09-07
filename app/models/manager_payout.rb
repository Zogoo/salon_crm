# BR-36: managers are on a flat monthly rate and never appear in earning_lines.
class ManagerPayout < ApplicationRecord
  belongs_to :staff_profile
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
