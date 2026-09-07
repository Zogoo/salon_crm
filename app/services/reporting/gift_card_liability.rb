module Reporting
  # BR-26 / BR-27: outstanding balance by **selling** location, aged by issue
  # month. Because expiry forfeits nothing (BR-30), old balances never fall off
  # the books by themselves — these buckets exist so they stay visible rather
  # than quietly accumulating.
  class GiftCardLiability < ApplicationService
    def initialize(location_ids: nil, as_of: Time.current)
      @location_ids = location_ids
      @as_of = as_of
    end

    def call
      scope = GiftCard.outstanding.where("sold_at <= ?", @as_of)
      scope = scope.where(sold_at_location_id: @location_ids) if @location_ids.present?

      cards = scope.includes(:sold_at_location).to_a
      {
        as_of: @as_of,
        total_outstanding_cents: cards.sum(&:current_balance_cents),
        card_count: cards.size,
        by_location: cards.group_by { |c| c.sold_at_location.name }
                          .transform_values { |cs| { count: cs.size, cents: cs.sum(&:current_balance_cents) } },
        by_issue_month: cards.group_by { |c| c.sold_at.strftime("%Y-%m") }
                             .transform_values { |cs| { count: cs.size, cents: cs.sum(&:current_balance_cents) } }
                             .sort.to_h,
        expired_but_spendable_cents: cards.select(&:expired?).sum(&:current_balance_cents)
      }
    end
  end
end
