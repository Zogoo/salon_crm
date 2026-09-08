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
  #
  # Compared as **dates**, not instants. FRS §23 says "at least 15 days before
  # their next monthly renewal date" — a day count. Comparing timestamps made
  # the boundary arbitrary: cancelling at 08:00 exactly 15 days out qualified
  # while 10:00 the same day did not, and "exactly 15 days" failed outright
  # because the two Time values were microseconds apart.
  def cancellation_effective_for(now = Time.current)
    zone = location&.tz || Time.zone
    days_of_notice = (current_period_end.in_time_zone(zone).to_date - now.in_time_zone(zone).to_date).to_i

    days_of_notice >= NOTICE_DAYS ? current_period_end : current_period_end + 1.month
  end

  def ledger_balance = membership_credit_transactions.sum(:amount)
  def drifted? = ledger_balance != credits_balance
end
