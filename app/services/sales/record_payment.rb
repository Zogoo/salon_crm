module Sales
  # Release 1 records payments; it does not process them (doc 08 §1). The
  # Manager types in what the terminal, the drawer or a Zelle transfer already
  # did.
  class RecordPayment < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(order:, method:, amount_cents:, actor: nil, reference: nil)
      @order = order
      @method = method.to_s
      @amount = amount_cents.to_i
      @actor = actor
      @reference = reference
    end

    def call
      raise Invalid, "unknown payment method" unless Payment::METHODS.include?(@method)
      raise Invalid, "amount must be positive" unless @amount.positive?

      ImmediateTransaction.call do
        @order.reload
        # BR-22: no overpayment. The surplus is a tip, entered as one.
        if @amount > @order.outstanding_cents
          raise Invalid, "overpayment_rejected"
        end

        payment = Payment.create!(
          order: @order, method: @method, processing: "recorded",
          amount_cents: @amount, reference: @reference,
          received_at: Time.current, received_by_user: @actor
        )
        AuditLog.record!(auditable: payment, action: "payment.recorded", actor: @actor,
                         changes: { method: @method, amount_cents: @amount })
        payment
      end
    end
  end
end
