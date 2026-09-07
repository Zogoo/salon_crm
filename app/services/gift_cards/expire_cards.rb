module GiftCards
  # BR-30: flags cards past their expiry **for reporting only**. It writes no
  # ledger row and changes no balance — the card stays redeemable, and the
  # client simply pays any difference if prices have moved since.
  class ExpireCards < ApplicationService
    def initialize(now: Time.current) = @now = now

    def call
      GiftCard.where(status: "active").where("expires_at < ?", @now)
              .update_all(status: "expired", updated_at: @now)
    end
  end
end
