module Memberships
  # Release 1's billing: the Manager records the $80 and that grants the credit.
  # In Release 2 the same cycle is closed by a Stripe `invoice.paid` webhook —
  # the entitlement logic below is built once and used by both.
  class RecordCyclePayment < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(membership:, method:, actor: nil, now: Time.current)
      @membership = membership
      @method = method.to_s
      @actor = actor
      @now = now
    end

    def call
      ImmediateTransaction.call do
        cycle = MembershipCycle.find_or_initialize_by(
          membership: @membership, period_start: @membership.current_period_start
        )
        raise Invalid, "cycle_already_charged" if cycle.persisted? && cycle.charged_at.present?

        order = billing_order
        cycle.assign_attributes(
          period_end: @membership.current_period_end,
          amount_cents: @membership.price_cents,
          charged_at: @now, order:, status: "paid"
        )
        cycle.save!

        grant_credit!(cycle)
        advance_period!
        cycle
      end
    end

    private

    # The charge is a liability until the credit is redeemed (BR-41).
    def billing_order
      order = Order.create!(
        number: Order.generate_number, client: @membership.client,
        location: @membership.location, kind: "membership", opened_by_user: @actor
      )
      OrderLineItem.create!(
        order:, purchasable: @membership,
        description: "Membership — #{@membership.current_period_start.to_date}",
        quantity: 1, unit_price_cents: @membership.price_cents,
        line_total_cents: @membership.price_cents,
        revenue_category: "membership_liability"
      )
      order.recalculate!
      Sales::RecordPayment.call(order:, method: @method,
                                amount_cents: @membership.price_cents, actor: @actor)
      Sales::SettleOrder.call(order:, actor: @actor)
      order
    end

    # BR-38: capped at 3. A charge that would exceed the cap grants nothing and
    # is recorded as forfeited — the member is still billed, which is what
    # "rollover up to a maximum of 3" means.
    def grant_credit!(cycle)
      if @membership.at_cap?
        cycle.update!(forfeited_to_cap: true, credit_granted: false)
        return
      end

      balance = @membership.credits_balance + 1
      MembershipCreditTransaction.create!(
        membership: @membership, kind: "grant", amount: 1, balance_after: balance,
        membership_cycle: cycle, performed_by_user: @actor, occurred_at: @now
      )
      @membership.update!(credits_balance: balance)
      cycle.update!(credit_granted: true)
    end

    def advance_period!
      @membership.update!(
        current_period_start: @membership.current_period_end,
        current_period_end: @membership.current_period_end + 1.month
      )
    end
  end
end
