module Sales
  # A discount given at the desk. It lowers what the client pays without any
  # money moving, so the reason and the person are the only record that it was
  # deliberate — both are required, and every one is audit-logged.
  #
  # Who may give how much: the Owner without limit; a Manager up to the
  # location's `manager_discount_limit_percent` of the order's services, counted
  # across every manual discount on the order, so two small discounts cannot
  # add up past the limit.
  #
  # Kept as its own ledger row rather than an edit to the order total, so the
  # reason survives into reporting (BR-48 nets it out of service revenue).
  class ApplyDiscount < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(order:, amount_cents:, actor:, reason: nil)
      @order = order
      @amount = amount_cents.to_i
      @actor = actor
      @reason = reason.to_s.strip.presence
    end

    def call
      raise Invalid, "amount_must_be_positive" unless @amount.positive?
      raise Invalid, "reason_required" unless @reason

      ImmediateTransaction.call do
        @order.reload.recalculate!
        raise Invalid, "order_not_open" unless @order.status == "open"
        # BR-22/BR-23: never below zero, and never below what has already been
        # taken — money taken comes back as a refund, not as a discount.
        raise Invalid, "discount_exceeds_remaining" if @amount > remaining
        enforce_limit!

        discount = OrderDiscount.create!(
          order: @order, kind: "manual", amount_cents: @amount,
          reason: @reason, applied_by_user: @actor
        )
        @order.recalculate!
        AuditLog.record!(auditable: @order, action: "order.discounted", actor: @actor,
                         changes: { amount_cents: @amount, reason: @reason,
                                    role: @actor&.role })
        discount
      end
    end

    def self.manager_limit_cents(order)
      (order.subtotal_cents * order.location.manager_discount_limit_percent / 100.0).floor
    end

    private

    def remaining
      [ @order.subtotal_cents - @order.discount_cents, @order.outstanding_cents ].min
    end

    def enforce_limit!
      return if @actor&.owner?
      raise Invalid, "discount_not_permitted" unless @actor&.manager?

      given = @order.order_discounts.where(kind: "manual").sum(:amount_cents)
      raise Invalid, "discount_above_manager_limit" if given + @amount > self.class.manager_limit_cents(@order)
    end
  end
end
