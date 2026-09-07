module Earnings
  # Rolls earning_lines up into one statement per therapist for the period.
  # Idempotent: rebuilding refreshes the totals rather than duplicating.
  class BuildStatements < ApplicationService
    def initialize(period:)
      @period = period
    end

    def call
      lines = EarningLine.in_period(@period.starts_on, @period.ends_on)
                         .includes(:staff_profile)
      by_staff = lines.group_by(&:staff_profile)

      ImmediateTransaction.call do
        by_staff.map do |staff, staff_lines|
          sessions = staff_lines.select { |l| l.duration_minutes.present? }
          tips = staff_lines.select { |l| l.source == "tip" }

          statement = EarningStatement.find_or_initialize_by(
            earning_period: @period, staff_profile: staff
          )
          adjustments = statement.persisted? ? statement.earning_adjustments.sum(:amount_cents) : 0
          service_cents = sessions.sum(&:amount_cents)
          tips_cents = tips.sum(&:amount_cents)

          statement.assign_attributes(
            total_sessions: sessions.sum(&:quantity),
            service_earnings_cents: service_cents,
            tips_cents: tips_cents,
            adjustments_cents: adjustments,
            gross_amount_cents: service_cents + tips_cents + adjustments,
            generated_at: Time.current
          )
          statement.save!
          statement
        end
      end
    end
  end
end
