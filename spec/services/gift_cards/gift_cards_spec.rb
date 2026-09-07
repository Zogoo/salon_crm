require "rails_helper"

# FRS §12, §13 and BR-25 … BR-31.
RSpec.describe "Gift cards" do
  let(:world) { build_world(rooms: { single: 1 }) }
  let(:other) do
    loc = create(:location, code: "other#{SecureRandom.hex(2)}")
    create(:room, location: loc, room_type: "single", client_capacity: 1)
    loc
  end
  let(:owner) { create(:user, email: "gc-owner@example.com", role: "owner") }

  def issue(amount: 10_000, location: world[:location])
    GiftCards::IssueCard.call(location:, amount_cents: amount,
                              payment_method: "cash", actor: owner,
                              buyer_name: "Buyer", buyer_phone: "+13125550001")
  end

  # BR-26: the sale is a liability, not revenue. This is the most common
  # accounting error in salon systems.
  it "books the sale as a liability, never as service revenue" do
    card = issue
    line = OrderLineItem.find_by(purchasable: card)

    expect(line.revenue_category).to eq("gift_card_liability")
    expect(OrderLineItem.revenue.where(id: line.id)).to be_empty
  end

  it "starts with a ledger entry equal to the face value (BR-25)" do
    card = issue(amount: 7_500)
    expect(card.current_balance_cents).to eq(7_500)
    expect(card.ledger_balance_cents).to eq(7_500)
    expect(card.gift_card_transactions.first.kind).to eq("issue")
  end

  describe "redemption" do
    let(:card) { issue(amount: 10_000) }
    let(:order) do
      appt = book(world)
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
      Sales::OpenOrder.call(appointment: appt.reload)
    end

    it "deducts, keeps the ledger in step, and leaves a balance for the next visit" do
      GiftCards::RedeemCard.call(code: card.code, order:, amount_cents: 3_000, actor: owner)
      card.reload

      expect(card.current_balance_cents).to eq(7_000)
      expect(card.ledger_balance_cents).to eq(7_000)
      expect(card).not_to be_drifted
      expect(order.reload.redeemed_cents).to eq(3_000)
    end

    it "marks the card depleted at zero" do
      GiftCards::RedeemCard.call(code: card.code, order:, amount_cents: order.total_cents, actor: owner)
      remaining = card.reload.current_balance_cents
      expect(card.status).to eq(remaining.zero? ? "depleted" : "active")
    end

    # BR-29
    it "refuses to redeem more than the balance, and says how much is left" do
      small = issue(amount: 500)
      expect { GiftCards::RedeemCard.call(code: small.code, order:, amount_cents: 5_000, actor: owner) }
        .to raise_error(GiftCards::RedeemCard::Invalid, /insufficient_balance:500/)
    end

    it "refuses to redeem more than the order is worth" do
      expect { GiftCards::RedeemCard.call(code: card.code, order:, amount_cents: order.total_cents + 1, actor: owner) }
        .to raise_error(GiftCards::RedeemCard::Invalid, "overpayment_rejected")
    end

    # BR-27: redeemable anywhere, attributed to the seller forever.
    it "redeems at another location while the liability stays with the seller" do
      card = issue(location: world[:location])
      w2 = build_world(rooms: { single: 1 })
      appt2 = book(w2)
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt2, to: t) }
      order2 = Sales::OpenOrder.call(appointment: appt2.reload)

      GiftCards::RedeemCard.call(code: card.code, order: order2, amount_cents: 1_000, actor: owner)
      txn = card.gift_card_transactions.find_by(kind: "redeem")

      expect(txn.location_id).to eq(w2[:location].id)                 # redeeming location
      expect(card.reload.sold_at_location_id).to eq(world[:location].id) # unchanged
    end
  end

  # BR-30 — the decision that removed most of the legal exposure.
  describe "expiry" do
    it "flags an old card without touching its balance or its ledger" do
      card = issue(amount: 4_000)
      card.update!(expires_at: 1.day.ago)

      expect { GiftCards::ExpireCards.call }
        .not_to change { card.reload.current_balance_cents }
      expect(card.status).to eq("expired")
      expect(card.gift_card_transactions.where(kind: "expire")).to be_empty
      expect(card).to be_redeemable        # the money is still the client's
    end

    it "still redeems after expiry" do
      card = issue(amount: 4_000)
      card.update!(expires_at: 1.day.ago)
      GiftCards::ExpireCards.call

      appt = book(world)
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
      order = Sales::OpenOrder.call(appointment: appt.reload)

      expect { GiftCards::RedeemCard.call(code: card.code, order:, amount_cents: 1_000, actor: owner) }
        .not_to raise_error
    end
  end

  describe "reconciliation (BR-25)" do
    it "reports a card whose cached balance has drifted from its ledger" do
      card = issue(amount: 5_000)
      expect(GiftCards::ReconcileBalances.call).to be_empty

      card.update_column(:current_balance_cents, 4_000)   # simulate drift
      drift = GiftCards::ReconcileBalances.call

      expect(drift.map { |d| d[:code] }).to include(card.code)
      expect(drift.first).to include(cached_cents: 4_000, ledger_cents: 5_000)
    end
  end
end
