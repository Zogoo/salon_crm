module Sales
  # Addendum §5: a fee the desk adds to the bill by hand (typically a card
  # surcharge). It is added to what the client owes, kept apart from service
  # revenue and tips, and reported as its own line.
  #
  # On an open order this is a normal checkout step. A settled visit is changed
  # only through Sales::CorrectVisit, which rebalances the payments with it.
  class SetTransactionFee < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(order:, amount_cents:, actor: nil)
      @order = order
      @amount = Integer(amount_cents, exception: false)
      @actor = actor
    end

    def call
      raise Invalid, "fee_invalid" if @amount.nil? || @amount.negative?

      ImmediateTransaction.call do
        @order.reload
        raise Invalid, "order_not_open" unless @order.status == "open"

        previous = @order.transaction_fee_cents
        @order.update!(transaction_fee_cents: @amount)
        @order.recalculate!
        # Lowering the fee below what has already been taken would leave the
        # client overpaid (BR-22).
        raise Invalid, "fee_below_amount_taken" if @order.outstanding_cents.negative?

        AuditLog.record!(auditable: @order, action: "order.transaction_fee_set", actor: @actor,
                         changes: { transaction_fee_cents: [ previous, @amount ] })
        @order
      end
    end
  end
end
