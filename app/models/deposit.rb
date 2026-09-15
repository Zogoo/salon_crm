# Money taken in the salon ahead of a visit (card, cash or Zelle).
#
# Until the visit is checked out it is the client's money held by the salon —
# a liability, not revenue (BR-48). At checkout it settles part of the bill; on
# an early cancellation it goes back; on a late cancellation or no-show the fee
# is taken from it and the rest goes back.
class Deposit < ApplicationRecord
  STATUSES = %w[held applied refunded forfeited].freeze

  belongs_to :appointment
  belongs_to :client
  belongs_to :location
  belongs_to :received_by_user, class_name: "User", optional: true
  belongs_to :resolved_by_user, class_name: "User", optional: true
  belongs_to :applied_order, class_name: "Order", optional: true

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :method, inclusion: { in: Payment::METHODS }
  validates :status, inclusion: { in: STATUSES }

  scope :held, -> { where(status: "held") }

  def held? = status == "held"
end
