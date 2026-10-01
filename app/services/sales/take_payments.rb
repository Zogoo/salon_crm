module Sales
  # Addendum §1: the client pays what is owed in one method, or split across
  # two — for example $70 on a gift card and $45 in cash. The parts must add up
  # to exactly what is outstanding; only then is the visit closed.
  #
  # All of it is one transaction: either every part is recorded and the order
  # settles, or nothing is — never a half-paid order with a gift card already
  # drawn down.
  class TakePayments < ApplicationService
    Invalid = Class.new(StandardError)

    GIFT_CARD = "gift_card".freeze
    MAX_PARTS = 2

    # parts: [{ method:, amount_cents:, code: (gift card only), reference: }]
    def initialize(order:, parts:, actor: nil)
      @order = order
      @parts = Array(parts).map { |p| p.to_h.symbolize_keys }
      @actor = actor
    end

    def call
      validate_shape!

      ImmediateTransaction.call do
        @order.reload.recalculate!
        raise Invalid, "order_not_open" unless @order.status == "open"

        due = @order.outstanding_cents
        given = @parts.sum { |p| p[:amount_cents].to_i }
        raise Invalid, "split_total_mismatch:#{due}" unless given == due

        @parts.each { |part| self.class.record!(@order, part, @actor) }
        SettleOrder.call(order: @order, actor: @actor)
        Earnings::GenerateForTip.call(order: @order.reload)
        @order
      end
    end

    # Shared with Sales::CorrectVisit, which re-enters a settled visit's money.
    def self.record!(order, part, actor)
      if part[:method].to_s == GIFT_CARD
        GiftCards::RedeemCard.call(code: part[:code].to_s, order:, amount_cents: part[:amount_cents], actor:)
      else
        RecordPayment.call(order:, method: part[:method], amount_cents: part[:amount_cents],
                           actor:, reference: part[:reference].presence)
      end
    end

    def self.valid_method?(method) = method.to_s == GIFT_CARD || Payment::METHODS.include?(method.to_s)

    private

    def validate_shape!
      raise Invalid, "payment_required" if @parts.empty? && @order.outstanding_cents.positive?
      raise Invalid, "too_many_parts" if @parts.size > MAX_PARTS
      @parts.each do |p|
        raise Invalid, "unknown_payment_method" unless self.class.valid_method?(p[:method])
        raise Invalid, "amount_must_be_positive" unless p[:amount_cents].to_i.positive?
        raise Invalid, "gift_card_code_required" if p[:method].to_s == GIFT_CARD && p[:code].blank?
      end
    end
  end
end
