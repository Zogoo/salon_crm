module Sales
  # BR-23: a payment is immutable. The sanctioned correction is to void it and
  # record a new one — never to edit. Owner only, and always audit-logged,
  # because voiding is how money would be made to disappear.
  class VoidPayment < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(payment:, actor:, reason:)
      @payment = payment
      @actor = actor
      @reason = reason
    end

    def call
      raise Invalid, "reason_required" if @reason.blank?
      raise Invalid, "already_voided" if @payment.status == "voided"

      ImmediateTransaction.call do
        @payment.update!(status: "voided", voided_by_user: @actor,
                         voided_at: Time.current, void_reason: @reason)

        # Voiding money off a settled order reopens it — the balance is
        # outstanding again and somebody has to take it.
        order = @payment.order.reload
        order.recalculate!
        order.update!(status: "open", closed_at: nil, closed_by_user: nil) if order.outstanding_cents.positive?

        AuditLog.record!(auditable: @payment, action: "payment.voided", actor: @actor,
                         changes: { amount_cents: @payment.amount_cents,
                                    method: @payment.method, reason: @reason })
        @payment
      end
    end
  end
end
