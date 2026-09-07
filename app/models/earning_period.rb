class EarningPeriod < ApplicationRecord
  STATUSES = %w[open in_review locked].freeze

  has_many :earning_statements, dependent: :destroy
  belongs_to :locked_by_user, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :locked, -> { where(status: "locked") }

  def locked? = status == "locked"

  # FRS §8: the 1st–15th and the 16th–end of month.
  def self.semi_monthly_bounds(date)
    if date.day <= 15
      [ date.beginning_of_month, date.beginning_of_month + 14.days ]
    else
      [ date.beginning_of_month + 15.days, date.end_of_month ]
    end
  end

  def self.for_date(date)
    starts_on, ends_on = semi_monthly_bounds(date)
    find_or_create_by!(starts_on:, ends_on:) { |p| p.kind = "semi_monthly" }
  end

  def lines = EarningLine.where(service_date: starts_on..ends_on)
end
