module Reporting
  # FRS §10, Addendum §3 and §5. Card / Cash / Zelle / Venmo / Online / Other,
  # and what the money was for:
  #
  #   Service revenue  (services, add-ons and enhancements, less discounts)
  # + Tips             (shown on their own line, and counted in the total)
  # + Transaction fees (added to the bill at checkout)
  # = Total revenue
  #
  # BR-48 still holds for everything else: a gift card sale and a membership
  # charge are liabilities, and a no-show fee is its own category. Those sit
  # beside the total, never inside it.
  #
  # A visit's money belongs to the day of the visit, not the moment it was
  # closed — so a visit corrected next week still reports on its own day.
  # Orders with no visit (a gift card sale, a membership charge) are dated when
  # they were closed.
  #
  # Deposits held for visits not yet checked out are the client's money, so
  # they are reported beside revenue, never inside it.
  class DailyRevenue < ApplicationService
    def initialize(location_ids:, from:, to:, breakdown: true)
      @location_ids = Array(location_ids)
      @from = from.to_date
      @to = to.to_date
      @breakdown = breakdown
    end

    def call
      discounts = discounts_cents
      service = category_total(OrderLineItem::REVENUE) - discounts
      tips = tips_cents
      fees = transaction_fees_cents
      data = {
        from: @from, to: @to,
        by_method: by_method,
        gross_service_revenue_cents: category_total(OrderLineItem::REVENUE),
        discounts_cents: discounts,
        service_revenue_cents: service,
        tips_cents: tips,
        transaction_fees_cents: fees,
        total_revenue_cents: service + tips + fees,
        gift_card_liability_cents: category_total(%w[gift_card_liability]),
        membership_liability_cents: category_total(%w[membership_liability]),
        fees_cents: category_total(%w[fee]),
        collected_cents: by_method.values.sum,
        deposits_received_cents: Deposit.where(location_id: @location_ids, received_at: range).sum(:amount_cents),
        deposits_held_cents: Deposit.held.where(location_id: @location_ids).sum(:amount_cents)
      }
      data[:by_location] = by_location if @breakdown && @location_ids.size > 1
      data
    end

    private

    def orders
      @orders ||= begin
        settled = Order.settled.where(location_id: @location_ids)
        visits = settled.where.not(appointment_id: nil)
                        .where(appointment_id: Appointment.where(starts_at: range).select(:id))
        others = settled.where(appointment_id: nil).where(closed_at: range)
        Order.where(id: visits.select(:id)).or(Order.where(id: others.select(:id)))
      end
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

    def transaction_fees_cents
      orders.sum(:transaction_fee_cents)
    end

    # System-wide view: the same four lines for each location.
    def by_location
      Location.where(id: @location_ids).order(:name).map do |location|
        row = self.class.call(location_ids: [ location.id ], from: @from, to: @to, breakdown: false)
        { location_id: location.id, name: location.name,
          service_revenue_cents: row[:service_revenue_cents], tips_cents: row[:tips_cents],
          transaction_fees_cents: row[:transaction_fees_cents],
          total_revenue_cents: row[:total_revenue_cents] }
      end
    end
  end
end
