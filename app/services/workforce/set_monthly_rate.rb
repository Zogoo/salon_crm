module Workforce
  # BR-36: the Manager's flat monthly rate, effective-dated like the therapist
  # ladder so payout history never changes retroactively.
  class SetMonthlyRate < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(staff_profile:, amount_cents:, effective_from:, actor: nil, note: nil)
      @profile = staff_profile
      @amount_cents = amount_cents.to_i
      @effective_from = effective_from.to_date
      @actor = actor
      @note = note
    end

    def call
      raise Invalid, "negative_amount" if @amount_cents.negative?

      ImmediateTransaction.call do
        EffectiveDating.close_open_periods!(@profile.staff_monthly_rates, @effective_from)
        @profile.staff_monthly_rates.create!(
          amount_cents: @amount_cents, effective_from: @effective_from,
          note: @note, created_by_user: @actor
        )
        AuditLog.record!(auditable: @profile, action: "staff.monthly_rate.set", actor: @actor,
                         changes: { effective_from: @effective_from })
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, e.record.errors.full_messages.join(", ")
    end
  end
end
