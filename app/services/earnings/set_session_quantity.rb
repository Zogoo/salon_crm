module Earnings
  # Addendum §4: the Owner types the number of sessions a therapist did at one
  # length over a date range, and the earnings follow.
  #
  # Generated lines stay as they are — they are the record of what the system
  # saw. The difference is entered as one manual correction line at the
  # therapist's rate, dated on the last day of the range, so the new figure is
  # what every earnings view shows and the change is visible and audited.
  class SetSessionQuantity < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(staff_profile:, duration_minutes:, from:, to:, quantity:, actor:)
      @staff = staff_profile
      @duration = duration_minutes.to_i
      @from = from.to_date
      @to = to.to_date
      @quantity = Integer(quantity, exception: false)
      @actor = actor
    end

    def call
      raise Invalid, "quantity_invalid" if @quantity.nil? || @quantity.negative?
      raise Invalid, "duration_invalid" unless ServiceVariant::LADDER.include?(@duration)
      raise Invalid, "range_invalid" if @to < @from

      ImmediateTransaction.call do
        current = EarningLine.sessions.where(staff_profile_id: @staff.id, duration_minutes: @duration)
                             .in_period(@from, @to).sum(:quantity)
        delta = @quantity - current
        next nil if delta.zero?

        rate = @staff.rate_cents_for(@duration, on: @to)
        raise Invalid, "no_rate_for_duration" unless rate

        AddManualLine.call(
          staff_profile: @staff, service_date: @to, actor: @actor,
          duration_minutes: @duration, quantity: delta, amount_cents: rate * delta,
          note: "#{@duration}-minute sessions #{@from}–#{@to} corrected from #{current} to #{@quantity}"
        )
      end
    rescue AddManualLine::Invalid => e
      raise Invalid, e.message
    end
  end
end
