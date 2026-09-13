require "rails_helper"

# FRS §23: the included monthly massage comes with hot stone, hot herbal
# compression and aromatherapy at no extra charge. Essential oil does not.
RSpec.describe "Membership complimentary enhancements" do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "ce-owner@example.com", role: "owner") }
  let(:location) { world[:location] }

  def enhancement(name, cents, complimentary:)
    service = create(:service, name:, kind: "enhancement",
                               complimentary_with_membership: complimentary)
    variant = create(:service_variant, service:, duration_minutes: 0)
    LocationPrice.create!(location:, service_variant: variant,
                          price_cents: cents, effective_from: Date.new(2026, 1, 1))
    variant
  end

  let(:hot_stone) { enhancement("Hot stone", 1_500, complimentary: true) }
  let(:essential_oil) { enhancement("Essential oil", 1_000, complimentary: false) }

  let(:membership) do
    m = Memberships::Enrol.call(client: world[:client], location:,
                                default_service_variant_id: world[:variant].id, actor: owner)
    m.update!(credits_balance: 1)
    m
  end

  def completed_order(variant_ids)
    appt = book(world, variant_ids:)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    Sales::OpenOrder.call(appointment: appt.reload, actor: owner)
  end

  it "costs a member nothing on top of the included massage" do
    order = completed_order([ world[:variant].id, hot_stone.id ])
    massage_price = order.subtotal_cents - 1_500

    Memberships::RedeemCredit.call(membership:, order:, actor: owner)

    # The credit covers the massage *and* the enhancement, so the member owes
    # nothing — this was charging them $15.
    expect(order.reload.discount_cents).to eq(massage_price + 1_500)
    expect(order.outstanding_cents).to eq(0)
  end

  it "still charges for an enhancement that is not included" do
    order = completed_order([ world[:variant].id, essential_oil.id ])
    massage_price = order.subtotal_cents - 1_000

    Memberships::RedeemCredit.call(membership:, order:, actor: owner)

    expect(order.reload.discount_cents).to eq(massage_price)
    # Essential oil is $10 and the member pays it.
    expect(order.outstanding_cents).to eq(1_000)
  end

  it "never credits more than the order is worth" do
    order = completed_order([ world[:variant].id, hot_stone.id ])
    # A valid booking still needs a timed service. Reduce its billed value to
    # exercise the cap without constructing an enhancement-only appointment.
    order.order_line_items.where(revenue_category: "service").update_all(unit_price_cents: 0, line_total_cents: 0)
    order.recalculate!

    Memberships::RedeemCredit.call(membership:, order:, actor: owner)

    expect(order.reload.discount_cents).to eq(order.subtotal_cents)
    expect(order.outstanding_cents).to eq(0)
  end
end
