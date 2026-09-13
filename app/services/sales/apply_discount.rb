module Sales
  # A discount given at the desk. Doc 01 §2.2 makes this Owner-only and
  # audit-logged: it lowers what the client pays without any money moving, so
  # the reason and the person are the only record that it was deliberate.
  #
  # Kept as its own ledger row rather than an edit to the order total, so the
  # reason survives into reporting (BR-48 counts it against service revenue,
  # not as a liability or a fee).
  class ApplyDiscount < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(order:, amount_cents:, actor:, reason: nil)
      @order = order
      @amount = amount_cents.to_i
      @actor = actor
      @reason = reason
    end

    def call
      raise Invalid, "amount_must_be_positive" unless @amount.positive?

      ImmediateTransaction.call do
        discount = OrderDiscount.create!(
          order: @order, kind: "manual", amount_cents: @amount,
          reason: @reason, applied_by_user: @actor
        )
        @order.recalculate!
        AuditLog.record!(auditable: @order, action: "order.discounted", actor: @actor,
                         changes: { amount_cents: @amount, reason: @reason })
        discount
      end
    end
  end
end
