module GiftCards
  # BR-29: never more than the remaining balance. BR-30: an expired card still
  # redeems — expiry is a reporting flag, not a forfeiture, so this checks the
  # balance and not the status.
  class RedeemCard < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(code:, order:, amount_cents:, actor: nil)
      @code = code
      @order = order
      @amount = amount_cents.to_i
      @actor = actor
    end

    def call
      ImmediateTransaction.call do
        card = GiftCard.lock.find_by(code: @code.to_s.strip.upcase)
        raise Invalid, "gift_card_not_found" unless card
        raise Invalid, "gift_card_void" if card.status == "void"
        raise Invalid, "amount must be positive" unless @amount.positive?

        if @amount > card.current_balance_cents
          raise Invalid, "insufficient_balance:#{card.current_balance_cents}"
        end
        if @amount > @order.reload.outstanding_cents
          raise Invalid, "overpayment_rejected"
        end

        balance_after = card.current_balance_cents - @amount
        GiftCardTransaction.create!(
          gift_card: card, kind: "redeem", amount_cents: -@amount,
          balance_after_cents: balance_after, order: @order,
          appointment: @order.appointment,
          redeemed_by_client: @order.client, performed_by_user: @actor,
          location: @order.location,        # the REDEEMING location, not the seller
          occurred_at: Time.current
        )
        card.update!(current_balance_cents: balance_after,
                     status: balance_after.zero? ? "depleted" : card.status)
        AuditLog.record!(auditable: card, action: "gift_card.redeemed", actor: @actor,
                         changes: { amount_cents: @amount, order: @order.number })
        card
      end
    end
  end
end
