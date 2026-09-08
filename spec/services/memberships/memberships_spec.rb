require "rails_helper"

# FRS §23 and BR-38 … BR-41.
RSpec.describe "Membership" do
  let(:world) { build_world(rooms: { single: 2 }) }
  let(:owner) { create(:user, email: "m-owner@example.com", role: "owner") }
  let(:client) { world[:client] }
  let(:included) { world[:variant] }   # the 60-minute massage the fee covers

  def enrol(location: world[:location])
    Memberships::Enrol.call(client:, location:, actor: owner,
                            default_service_variant_id: included.id)
  end

  def pay_cycle(membership) = Memberships::RecordCyclePayment.call(membership:, method: "card", actor: owner)

  it "enrols at $80/month tied to the joining location (BR-39a)" do
    m = enrol
    expect(m.price_cents).to eq(8_000)
    expect(m.location_id).to eq(world[:location].id)
    expect(m.credits_balance).to be_zero
  end

  it "refuses a second membership for the same client" do
    enrol
    expect { enrol }.to raise_error(Memberships::Enrol::Invalid, "already_a_member")
  end

  describe "billing and credits (BR-38, BR-41)" do
    it "grants one credit per recorded payment and books it as a liability" do
      m = enrol
      pay_cycle(m)

      expect(m.reload.credits_balance).to eq(1)
      line = OrderLineItem.find_by(purchasable: m)
      expect(line.revenue_category).to eq("membership_liability")
    end

    it "rolls credits over and caps the balance at three" do
      m = enrol
      4.times { pay_cycle(m.reload) }

      expect(m.reload.credits_balance).to eq(3)
      # The member is still charged at the cap — that is what "rollover up to a
      # maximum of 3" means — and the forfeit is recorded rather than hidden.
      expect(m.membership_cycles.count).to eq(4)
      expect(m.membership_cycles.where(forfeited_to_cap: true).count).to eq(1)
      expect(m.ledger_balance).to eq(3)
    end

    it "advances the period on each charge" do
      m = enrol
      first_end = m.current_period_end
      pay_cycle(m)
      expect(m.reload.current_period_start).to eq(first_end)
    end
  end

  describe "redemption (BR-39)" do
    def order_for(variant, location: world[:location])
      w = location == world[:location] ? world : nil
      appt = book(w || world, variant_ids: [ variant.id ])
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
      Sales::OpenOrder.call(appointment: appt.reload)
    end

    it "covers the included 60-minute massage in full" do
      m = enrol
      pay_cycle(m)
      order = order_for(included)

      credited = Memberships::RedeemCredit.call(membership: m.reload, order:, actor: owner)
      expect(credited).to eq(order.subtotal_cents)
      expect(order.reload.outstanding_cents).to be_zero
      expect(m.reload.credits_balance).to be_zero
    end

    it "consumes the credit and charges the difference on an upgrade" do
      upgrade = create(:service_variant, service: world[:service], duration_minutes: 90,
                                         base_price_cents: 12_000)
      LocationPrice.create!(location: world[:location], service_variant: included,
                            price_cents: 8_000, effective_from: Date.new(2026, 1, 1))
      LocationPrice.create!(location: world[:location], service_variant: upgrade,
                            price_cents: 12_000, effective_from: Date.new(2026, 1, 1))
      m = enrol
      pay_cycle(m)
      order = order_for(upgrade)

      credited = Memberships::RedeemCredit.call(membership: m.reload, order:, actor: owner)
      expect(credited).to eq(8_000)                     # worth the included massage
      expect(order.reload.outstanding_cents).to eq(4_000)  # the member pays the difference
      expect(m.reload.credits_balance).to be_zero       # the credit is consumed
    end

    it "refuses to redeem with no credit" do
      m = enrol
      expect { Memberships::RedeemCredit.call(membership: m, order: order_for(included), actor: owner) }
        .to raise_error(Memberships::RedeemCredit::Invalid, "no_membership_credit")
    end

    # BR-39a — the deliberate asymmetry with gift cards.
    it "refuses redemption away from the home location without an override" do
      m = enrol
      pay_cycle(m)
      w2 = build_world(rooms: { single: 1 })
      appt = book(w2)
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
      away_order = Sales::OpenOrder.call(appointment: appt.reload)

      expect { Memberships::RedeemCredit.call(membership: m.reload, order: away_order, actor: owner) }
        .to raise_error(Memberships::RedeemCredit::Invalid, "membership_wrong_location")
    end

    it "allows it with an Owner override, and records who approved" do
      m = enrol
      pay_cycle(m)
      w2 = build_world(rooms: { single: 1 })
      appt = book(w2)
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
      away_order = Sales::OpenOrder.call(appointment: appt.reload)

      Memberships::RedeemCredit.call(membership: m.reload, order: away_order,
                                     actor: owner, cross_location_approver: owner)
      txn = m.membership_credit_transactions.find_by(kind: "redeem")
      expect(txn.cross_location_approved_by_user_id).to eq(owner.id)
    end
  end

  # BR-40
  describe "cancellation notice" do
    it "ends at the current period when notice is 15 days or more" do
      m = enrol
      m.update!(current_period_end: 20.days.from_now)
      Memberships::RequestCancellation.call(membership: m, actor: owner)

      expect(m.reload.status).to eq("pending_cancellation")
      expect(m.cancellation_effective_at.to_date).to eq(m.current_period_end.to_date)
    end

    it "ends after the FOLLOWING period when notice is short — the next charge still happens" do
      m = enrol
      m.update!(current_period_end: 5.days.from_now)
      Memberships::RequestCancellation.call(membership: m, actor: owner)

      expect(m.reload.cancellation_effective_at.to_date)
        .to eq((m.current_period_end + 1.month).to_date)
    end

    # The boundary itself. FRS §23 says "at least 15 days", which is a rule
    # about days — comparing instants made it arbitrary (08:00 qualified,
    # 10:00 the same day did not) and rejected exactly-15-days outright.
    it "treats exactly 15 days as sufficient notice" do
      m = enrol
      m.update!(current_period_end: 15.days.from_now)

      expect(m.cancellation_effective_for.to_date).to eq(m.current_period_end.to_date)
    end

    it "treats 14 days as short notice" do
      m = enrol
      m.update!(current_period_end: 14.days.from_now)

      expect(m.cancellation_effective_for.to_date)
        .to eq((m.current_period_end + 1.month).to_date)
    end

    it "counts days in the salon's zone, so the hour of day never decides it" do
      m = enrol
      tz = m.location.tz
      renewal = tz.local(2026, 10, 1, 9, 0)
      m.update!(current_period_end: renewal)

      # Both are 15 days before the renewal date; neither may be treated
      # differently because of the time of day.
      early = tz.local(2026, 9, 16, 8, 0)
      late  = tz.local(2026, 9, 16, 22, 0)

      expect(m.cancellation_effective_for(early).to_date).to eq(renewal.to_date)
      expect(m.cancellation_effective_for(late).to_date).to eq(renewal.to_date)
    end
  end
end
