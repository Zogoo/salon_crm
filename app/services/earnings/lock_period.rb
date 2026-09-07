module Earnings
  # BR-37: once locked, the period's lines are read-only and corrections flow
  # into the next period as adjustments.
  class LockPeriod < ApplicationService
    def initialize(period:, actor:)
      @period = period
      @actor = actor
    end

    def call
      ImmediateTransaction.call do
        BuildStatements.call(period: @period)
        @period.update!(status: "locked", locked_at: Time.current, locked_by_user: @actor)
        AuditLog.record!(auditable: @period, action: "earning_period.locked", actor: @actor,
                         changes: { starts_on: @period.starts_on.to_s,
                                    ends_on: @period.ends_on.to_s })
        @period
      end
    end
  end
end
