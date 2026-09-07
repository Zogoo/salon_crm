module Earnings
  # BR-24a: a tip is 100% the therapist's, so it lands in earnings and never in
  # revenue.
  class GenerateForTip < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      appt = @order.appointment
      return [] unless appt
      date = appt.starts_at.in_time_zone(appt.location.tz).to_date

      ImmediateTransaction.call do
        @order.tip_allocations.filter_map do |alloc|
          next if alloc.amount_cents.zero?
          next if EarningLine.exists?(tip_allocation_id: alloc.id)

          EarningLine.create!(
            staff_profile_id: alloc.staff_profile_id, location: appt.location,
            service_date: date, source: "tip", appointment: appt,
            tip_allocation: alloc, amount_cents: alloc.amount_cents
          )
        end
      end
    end
  end
end
