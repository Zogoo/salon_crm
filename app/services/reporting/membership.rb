module Reporting
  # FRS §23 / doc 05 §"Reporting". BR-41: billed membership money is a
  # liability until the credit is redeemed, so this report counts credits
  # outstanding rather than treating the billings as revenue.
  class Membership < ApplicationService
    def initialize(location_ids:, from:, to:)
      @location_ids = Array(location_ids)
      @from = from.to_date
      @to = to.to_date
    end

    def call
      members = ::Membership.where(location_id: @location_ids)
      active = members.where(status: "active")

      {
        from: @from, to: @to,
        active_members: active.count,
        credits_outstanding: active.sum(:credits_balance),
        # BR-38 caps accumulation at 3; members sitting at the cap are the ones
        # who are paying and not visiting.
        at_cap: active.where(credits_balance: ::Membership::CREDIT_CAP..).count,
        enrolled_in_period: members.where(enrolled_at: window).count,
        pending_cancellations: members.where.not(cancellation_requested_at: nil)
                                      .where(status: "active").count,
        credits_granted: transactions("grant").sum(:amount),
        credits_redeemed: transactions("redeem").sum(:amount).abs,
        cross_location_overrides: transactions("redeem")
                                    .where.not(cross_location_approved_by_user_id: nil).count,
        # BR-41: what the salon still owes in unredeemed entitlements.
        liability_cents: active.sum { |m| m.credits_balance * m.price_cents }
      }
    end

    private

    def window = @from.beginning_of_day..@to.end_of_day

    def transactions(kind)
      MembershipCreditTransaction.where(kind:, occurred_at: window)
                                 .where(membership_id: ::Membership.where(location_id: @location_ids))
    end
  end
end
