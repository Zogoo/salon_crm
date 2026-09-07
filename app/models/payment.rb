# BR-23: immutable once created. Void or refund and re-enter; never edit.
class Payment < ApplicationRecord
  METHODS = %w[card cash zelle online other].freeze

  belongs_to :order
  belongs_to :received_by_user, class_name: "User", optional: true
  belongs_to :voided_by_user, class_name: "User", optional: true

  validates :method, inclusion: { in: METHODS }
  validates :amount_cents, numericality: { greater_than: 0 }
  validate  :immutable_once_captured, on: :update

  scope :captured, -> { where(status: "captured") }

  private

  # Only the void fields may change after creation.
  def immutable_once_captured
    changed_keys = changed - %w[status voided_by_user_id voided_at void_reason updated_at]
    return if changed_keys.empty?

    errors.add(:base, "a payment cannot be edited (BR-23) — void it and record a new one")
  end
end
