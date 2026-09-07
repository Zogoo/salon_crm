module GiftCards
  # BR-25: the balance column is a cache of the ledger. This asserts they agree
  # and reports every card that has drifted, so a bug shows up as a report
  # rather than as money quietly going missing.
  class ReconcileBalances < ApplicationService
    def call
      drifted = GiftCard.includes(:gift_card_transactions).select(&:drifted?)
      drifted.map do |card|
        { id: card.id, code: card.code,
          cached_cents: card.current_balance_cents,
          ledger_cents: card.ledger_balance_cents }
      end
    end
  end
end
