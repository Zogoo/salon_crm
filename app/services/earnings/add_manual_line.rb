module Earnings
  # FRS §4: the Owner may add sessions and tips by hand, for corrections or
  # off-system work. Every manual line is flagged and audit-logged so a payout
  # can always be traced back to who entered it.
  class AddManualLine < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(staff_profile:, service_date:, actor:, duration_minutes: nil,
                   quantity: 1, amount_cents: nil, note: nil)
      @staff = staff_profile
      @date = service_date.to_date
      @actor = actor
      @duration = duration_minutes&.to_i
      @quantity = quantity.to_i
      @amount = amount_cents
      @note = note
    end

    def call
      raise Invalid, "period_locked" if locked_period?
      if @duration && !ServiceVariant::LADDER.include?(@duration)
        raise Invalid, "duration must be one of #{ServiceVariant::LADDER.join(', ')}"
      end

      rate = @duration ? @staff.rate_cents_for(@duration, on: @date) : nil
      amount = @amount || (rate ? rate * @quantity : nil)
      raise Invalid, "no rate for that duration and no amount given" unless amount

      ImmediateTransaction.call do
        line = EarningLine.create!(
          staff_profile: @staff, location: @staff.location, service_date: @date,
          source: "manual", duration_minutes: @duration, quantity: @quantity,
          rate_cents: rate, amount_cents: amount,
          created_by_user: @actor, note: @note
        )
        AuditLog.record!(auditable: line, action: "earning_line.manual", actor: @actor,
                         changes: { staff: @staff.display_name, date: @date.to_s,
                                    amount_cents: amount })
        line
      end
    end

    private

    # BR-37: a locked period is read-only.
    def locked_period?
      starts_on, ends_on = EarningPeriod.semi_monthly_bounds(@date)
      EarningPeriod.locked.exists?(starts_on:, ends_on:)
    end
  end
end
