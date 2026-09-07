module GiftCards
  # BR-26: selling a gift card is a liability, not revenue. Revenue is
  # recognised when the card is redeemed against a service.
  class IssueCard < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(location:, amount_cents:, payment_method:, actor: nil, code: nil,
                   buyer_client: nil, buyer_name: nil, buyer_phone: nil,
                   recipient_client: nil, recipient_name: nil, recipient_phone: nil)
      @location = location
      @amount = amount_cents.to_i
      @payment_method = payment_method.to_s
      @actor = actor
      @code = code.presence
      @buyer_client = buyer_client
      @buyer_name = buyer_name
      @buyer_phone = buyer_phone
      @recipient_client = recipient_client
      @recipient_name = recipient_name
      @recipient_phone = recipient_phone
    end

    def call
      raise Invalid, "amount must be positive" unless @amount.positive?
      raise Invalid, "unknown payment method" unless Payment::METHODS.include?(@payment_method)

      ImmediateTransaction.call do
        card = GiftCard.create!(
          code: @code || GiftCard.generate_code,
          origin: "physical",                       # digital purchase is Release 2
          initial_value_cents: @amount,
          current_balance_cents: @amount,
          purchase_payment_method: @payment_method,
          buyer_client: @buyer_client, buyer_name: @buyer_name, buyer_phone: @buyer_phone,
          recipient_client: @recipient_client, recipient_name: @recipient_name,
          recipient_phone: @recipient_phone,
          sold_at: Time.current, sold_by_user: @actor,
          sold_at_location: @location,              # BR-27, permanent
          expires_at: Time.current + @location.gift_card_expiry_months.months
        )

        GiftCardTransaction.create!(
          gift_card: card, kind: "issue", amount_cents: @amount,
          balance_after_cents: @amount, performed_by_user: @actor,
          location: @location, occurred_at: Time.current
        )

        # The sale is booked as a liability order at the selling location.
        order = Order.create!(
          number: Order.generate_number, client: @buyer_client, location: @location,
          kind: "gift_card", opened_by_user: @actor
        )
        OrderLineItem.create!(
          order:, purchasable: card, description: "Gift card #{card.code}",
          quantity: 1, unit_price_cents: @amount, line_total_cents: @amount,
          revenue_category: "gift_card_liability"
        )
        order.recalculate!
        Sales::RecordPayment.call(order:, method: @payment_method,
                                  amount_cents: @amount, actor: @actor)
        Sales::SettleOrder.call(order:, actor: @actor)

        AuditLog.record!(auditable: card, action: "gift_card.issued", actor: @actor,
                         changes: { amount_cents: @amount, location: @location.code })
        card
      end
    end
  end
end
