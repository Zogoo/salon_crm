module Earnings
  # Manual earnings may be corrected while their pay period is open. The old
  # and new values remain in the audit trail; generated session and tip lines
  # continue to be derived from appointments and cannot be hand-edited.
  class UpdateManualLine < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(line:, amount_cents:, actor:, note: nil)
      @line = line
      @amount = amount_cents.to_i
      @actor = actor
      @note = note
    end

    def call
      raise Invalid, "only_manual_lines_are_editable" unless @line.source == "manual"
      raise Invalid, "period_locked" if locked_period?

      previous = { amount_cents: @line.amount_cents, note: @line.note }
      @line.update!(amount_cents: @amount, note: @note)
      AuditLog.record!(
        auditable: @line, action: "earning_line.updated", actor: @actor,
        changes: { from: previous, to: { amount_cents: @amount, note: @note } }
      )
      @line
    end

    private

    def locked_period?
      starts_on, ends_on = EarningPeriod.semi_monthly_bounds(@line.service_date)
      EarningPeriod.locked.exists?(starts_on:, ends_on:)
    end
  end
end
