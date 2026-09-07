module Reporting
  # FRS §4 and §8, verbatim: quantity and earnings for each of the six rungs,
  # tips, total. `quantity` counts sessions **as paid** (BR-33), so a 60+30
  # combination is one unit in the 90-minute row, not one in each of 60 and 30.
  class StaffEarnings < ApplicationService
    def initialize(staff_profile:, from:, to:)
      @staff = staff_profile
      @from = from.to_date
      @to = to.to_date
    end

    def call
      lines = EarningLine.where(staff_profile_id: @staff.id).in_period(@from, @to)
      sessions = lines.select { |l| l.duration_minutes.present? }

      rows = ServiceVariant::LADDER.map do |duration|
        matching = sessions.select { |l| l.duration_minutes == duration }
        { duration_minutes: duration,
          quantity: matching.sum(&:quantity),
          earnings_cents: matching.sum(&:amount_cents) }
      end

      tips = lines.select { |l| l.source == "tip" }.sum(&:amount_cents)
      service_total = rows.sum { |r| r[:earnings_cents] }

      {
        staff_profile_id: @staff.id, display_name: @staff.display_name,
        period: { from: @from, to: @to },
        sessions: rows,
        tips_cents: tips,
        total_cents: service_total + tips
      }
    end
  end
end
