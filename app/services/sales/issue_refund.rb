module Sales
  # Money going back out. Doc 01 §2.2 lists a refund among the writes only the
  # Owner may make, and every one of them writes an audit row — a refund moves
  # money off the books, so who issued it and why has to survive.
  #
  # BR-23: the payment itself is never edited. The refund is its own row
  # pointing at the payment, so the original capture stays on the record.
  class IssueRefund < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(order:, payment:, amount_cents:, actor:, reason: "owner_discretion")
      @order = order
      @payment = payment
      @amount = amount_cents.to_i
      @actor = actor
      @reason = reason
    end

    def call
      raise Invalid, "amount_must_be_positive" unless @amount.positive?

      ImmediateTransaction.call do
        # Re-read inside the lock: refunds issued between loading the payment
        # and writing this one would otherwise not be counted, letting two
        # concurrent refunds together exceed what was captured.
        already = Refund.where(payment_id: @payment.id).sum(:amount_cents)
        raise Invalid, "refund_exceeds_payment" if @amount + already > @payment.amount_cents

        refund = Refund.create!(
          order: @order, payment: @payment, amount_cents: @amount,
          reason: @reason, issued_by_user: @actor, issued_at: Time.current
        )
        AuditLog.record!(auditable: @payment, action: "payment.refunded", actor: @actor,
                         changes: { amount_cents: @amount, reason: @reason,
                                    refunded_to_date: already + @amount })
        refund
      end
    end
  end
end
