module Memberships
  # BR-39: the included 60-minute massage costs $0. Anything else consumes the
  # credit and charges the **difference** between that service's list price and
  # the included massage's, both at the redeeming location on the day.
  #
  # BR-39a: redeeming away from the home location needs an Owner/Manager
  # override, and the approver is recorded on the ledger row.
  class RedeemCredit < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(membership:, order:, actor: nil, cross_location_approver: nil, now: Time.current)
      @membership = membership
      @order = order
      @actor = actor
      @approver = cross_location_approver
      @now = now
    end

    def call
      ImmediateTransaction.call do
        # Re-read under the write lock. The object handed in was loaded before
        # the transaction, so trusting its balance lets several tills each
        # spend the same credit — BEGIN IMMEDIATE serialises the writes, not
        # the reads that preceded them.
        membership = Membership.lock.find(@membership.id)
        raise Invalid, "no_membership_credit" unless membership.credits_balance.positive?

        unless membership.redeemable_at?(@order.location_id)
          raise Invalid, "membership_wrong_location" unless @approver
        end

        credit_cents = entitlement_value
        raise Invalid, "nothing_to_credit" unless credit_cents.positive?

        OrderDiscount.create!(
          order: @order, kind: "membership_upgrade_credit",
          amount_cents: credit_cents, applied_by_user: @actor,
          reason: "Membership credit"
        )

        balance = membership.credits_balance - 1
        MembershipCreditTransaction.create!(
          membership:, kind: "redeem", amount: -1, balance_after: balance,
          appointment: @order.appointment, performed_by_user: @actor,
          cross_location_approved_by_user: @approver, occurred_at: @now,
          note: @approver ? "cross-location override" : nil
        )
        membership.update!(credits_balance: balance)
        @membership.reload
        @order.recalculate!
        credit_cents
      end
    end

    private

    # The credit is worth the included 60-minute massage at this location today.
    # The member pays whatever the chosen service costs above that.
    def entitlement_value
      variant = @membership.default_service_variant
      return 0 unless variant

      included = Catalogue::ResolvePrice.call(
        variant:, location: @order.location, on: @order.location.today
      )
      # Never credit more than the order is worth.
      [ included, @order.subtotal_cents ].min
    end
  end
end
