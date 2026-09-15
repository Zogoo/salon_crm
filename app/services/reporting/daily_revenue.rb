module Reporting
  # FRS §10. Card / Cash / Zelle / Online / Other, tips, total.
  #
  # BR-48 is the rule this must never break: service revenue comes from
  # completed appointments' service lines. A gift card sale and a membership
  # charge are **liabilities**, and a no-show fee is its own category. Summing
  # order totals would silently mix all three.
  #
  # Manual discounts are netted out of service revenue — a $80 service sold for
  # $60 earned $60. A membership credit is not: that session was delivered and
  # paid for from the membership liability.
  #
  # Deposits held for visits not yet checked out are the client's money, so
  # they are reported beside revenue, never inside it.
  class DailyRevenue < ApplicationService
    def initialize(location_ids:, from:, to:)
      @location_ids = Array(location_ids)
      @from = from.to_date
      @to = to.to_date
    end

    def call
      discounts = discounts_cents
      {
        from: @from, to: @to,
        by_method: by_method,
        gross_service_revenue_cents: category_total(OrderLineItem::REVENUE),
        discounts_cents: discounts,
        service_revenue_cents: category_total(OrderLineItem::REVENUE) - discounts,
        gift_card_liability_cents: category_total(%w[gift_card_liability]),
        membership_liability_cents: category_total(%w[membership_liability]),
        fees_cents: category_total(%w[fee]),
        tips_cents: tips_cents,
        collected_cents: by_method.values.sum,
        deposits_received_cents: Deposit.where(location_id: @location_ids, received_at: range).sum(:amount_cents),
        deposits_held_cents: Deposit.held.where(location_id: @location_ids).sum(:amount_cents)
      }
    end

    private

    def orders
      Order.settled.where(location_id: @location_ids)
           .where(closed_at: range)
    end

    def range
      # Day boundaries in the location's own zone (doc 03 §5).
      tz = Location.where(id: @location_ids).first&.tz || Time.zone
      tz.local(@from.year, @from.month, @from.day).beginning_of_day..
        tz.local(@to.year, @to.month, @to.day).end_of_day
    end

    def by_method
      @by_method ||= Payment.captured
                            .where(order_id: orders.select(:id))
                            .group(:method).sum(:amount_cents)
                            .then { |h| Payment::METHODS.index_with { |m| h[m] || 0 } }
    end

    def category_total(categories)
      OrderLineItem.where(order_id: orders.select(:id), revenue_category: categories)
                   .sum(:line_total_cents)
    end

    def discounts_cents
      OrderDiscount.where(order_id: orders.where(kind: "service").select(:id), kind: "manual")
                   .sum(:amount_cents)
    end

    def tips_cents
      TipAllocation.where(order_id: orders.select(:id)).sum(:amount_cents)
    end
  end
end
