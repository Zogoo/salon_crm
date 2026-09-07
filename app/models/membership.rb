class Membership < ApplicationRecord
  STATUSES = %w[active pending_cancellation cancelled past_due].freeze
  CREDIT_CAP = 3                 # BR-38
  NOTICE_DAYS = 15               # BR-40

  belongs_to :client
  belongs_to :location
  belongs_to :default_service_variant, class_name: "ServiceVariant", optional: true
  has_many :membership_cycles, dependent: :destroy
  has_many :membership_credit_transactions, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :credits_balance,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: CREDIT_CAP }

  scope :active, -> { where(status: %w[active pending_cancellation]) }

  def at_cap? = credits_balance >= CREDIT_CAP

  # BR-39a: redeemable at the home location; anywhere else needs an override.
  def redeemable_at?(location_id) = location_id == self.location_id

  # BR-40: notice inside the window pushes the end to the *following* period.
  def cancellation_effective_for(now = Time.current)
    if (current_period_end - now) >= NOTICE_DAYS.days
      current_period_end
    else
      current_period_end + 1.month
    end
  end

  def ledger_balance = membership_credit_transactions.sum(:amount)
  def drifted? = ledger_balance != credits_balance
end
