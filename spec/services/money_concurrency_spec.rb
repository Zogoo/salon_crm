require "rails_helper"

# The booking race is covered by concurrency_spec. These are the *money* races,
# which were never tested: two tills redeeming the same gift card, two
# redeeming the last membership credit, and a double-settle.
#
# All three rely on the same thing booking does — BEGIN IMMEDIATE serialising
# writers (doc 08 §2) — so if that ever regresses, these fail too.
RSpec.describe "Money concurrency", type: :model do
  self.use_transactional_tests = false

  before { DatabaseCleaner.strategy = :deletion }
  after  { DatabaseCleaner.clean }

  let(:owner) { create(:user, email: "mc-owner@example.com", role: "owner") }

  def completed_order(world)
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    Sales::OpenOrder.call(appointment: appt.reload)
  end

  def race(count)
    results = Queue.new
    Array.new(count) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          results << (yield)
        rescue => e
          results << e
        end
      end
    end.each(&:join)
    Array.new(results.size) { results.pop }
  end

  it "lets only one till spend the last of a gift card" do
    world = build_world(rooms: { single: 6 }, therapists: 6)
    card = GiftCards::IssueCard.call(location: world[:location], amount_cents: 3_000,
                                     payment_method: "cash", actor: owner, buyer_name: "B")
    # Six separate orders, each trying to take the whole remaining balance.
    orders = Array.new(6) { |i| completed_order(world.merge(at: world[:at] + (i * 2).hours)) }

    outcomes = race(6) do
      index = Thread.current.object_id % orders.size
      GiftCards::RedeemCard.call(code: card.code, order: orders[index],
                                 amount_cents: 3_000, actor: owner)
    end

    succeeded = outcomes.count { |o| o.is_a?(GiftCard) }
    expect(succeeded).to eq(1)
    expect(card.reload.current_balance_cents).to be_zero
    # The ledger must still agree with the cache — a lost update would show here.
    expect(card).not_to be_drifted
    expect(card.gift_card_transactions.where(kind: "redeem").count).to eq(1)
  end

  it "lets only one till spend the last membership credit" do
    world = build_world(rooms: { single: 6 }, therapists: 6)
    membership = Memberships::Enrol.call(client: world[:client], location: world[:location],
                                         actor: owner, default_service_variant_id: world[:variant].id)
    Memberships::RecordCyclePayment.call(membership:, method: "cash", actor: owner)
    expect(membership.reload.credits_balance).to eq(1)

    orders = Array.new(5) { |i| completed_order(world.merge(at: world[:at] + (i * 2).hours)) }

    outcomes = race(5) do
      index = Thread.current.object_id % orders.size
      Memberships::RedeemCredit.call(membership: Membership.find(membership.id),
                                     order: orders[index], actor: owner)
    end

    succeeded = outcomes.count { |o| o.is_a?(Integer) }
    expect(succeeded).to eq(1)
    expect(membership.reload.credits_balance).to be_zero
    expect(membership).not_to be_drifted
  end

  it "settles an order once even when two tills press it together" do
    world = build_world(rooms: { single: 1 })
    order = completed_order(world)
    Sales::RecordPayment.call(order:, method: "card", amount_cents: order.total_cents, actor: owner)

    outcomes = race(4) { Sales::SettleOrder.call(order: Order.find(order.id), actor: owner) }

    expect(outcomes.count { |o| o.is_a?(Order) }).to be >= 1
    expect(order.reload.status).to eq("paid")
    # BR-17: a session is paid once, however many times settle was pressed.
    expect(EarningLine.where(appointment_id: order.appointment_id, source: "session").count)
      .to eq(order.appointment.staff_profiles.count)
  end
end
