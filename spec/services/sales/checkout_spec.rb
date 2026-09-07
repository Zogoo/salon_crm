require "rails_helper"

# FRS §5, §7, §21 and BR-19, BR-22, BR-23, BR-24.
RSpec.describe "Checkout" do
  def complete(appt)
    %w[checked_in in_progress completed].each do |to|
      Scheduling::TransitionStatus.call(appointment: appt, to:)
    end
    appt.reload
  end

  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:appointment) { complete(book(world)) }
  let(:order) { Sales::OpenOrder.call(appointment:) }

  describe "opening an order" do
    it "prices from the snapshot taken at booking, not today's menu" do
      LocationPrice.create!(location: world[:location], service_variant: world[:variant],
                            price_cents: 999_99, effective_from: Date.current)
      expect(order.total_cents).to eq(appointment.total_price_cents)
    end

    it "is idempotent — reopening returns the same order" do
      first = order
      expect(Sales::OpenOrder.call(appointment:).id).to eq(first.id)
    end
  end

  describe "payment" do
    it "records a payment without processing it" do
      Sales::RecordPayment.call(order:, method: "card", amount_cents: order.total_cents)
      expect(order.reload.outstanding_cents).to be_zero
      expect(order.payments.first.processing).to eq("recorded")
    end

    # FRS §5, §21: a single appointment may be settled across two methods.
    it "accepts a split across two methods" do
      half = order.total_cents / 2
      Sales::RecordPayment.call(order:, method: "cash", amount_cents: half)
      Sales::RecordPayment.call(order:, method: "zelle", amount_cents: order.total_cents - half)

      expect(order.reload.outstanding_cents).to be_zero
      expect(order.payments.pluck(:method)).to contain_exactly("cash", "zelle")
    end

    # BR-22: no overpayment — the surplus must be entered as a tip.
    it "rejects an overpayment" do
      expect {
        Sales::RecordPayment.call(order:, method: "cash", amount_cents: order.total_cents + 1)
      }.to raise_error(Sales::RecordPayment::Invalid, "overpayment_rejected")
    end

    # BR-23: immutable once captured.
    it "refuses to edit a captured payment" do
      payment = Sales::RecordPayment.call(order:, method: "cash", amount_cents: 100)
      payment.amount_cents = 5
      expect(payment.save).to be(false)
      expect(payment.errors.full_messages.join).to match(/cannot be edited/)
    end

    it "allows a payment to be voided, which is the sanctioned correction" do
      payment = Sales::RecordPayment.call(order:, method: "cash", amount_cents: 100)
      expect(payment.update(status: "voided", voided_at: Time.current, void_reason: "wrong amount"))
        .to be(true)
    end
  end

  describe "tips (BR-24, BR-24a)" do
    it "gives the whole tip to the single performing therapist" do
      Sales::AllocateTips.call(order:, amount_cents: 2_000)
      expect(order.tip_allocations.sum(:amount_cents)).to eq(2_000)
      expect(order.tip_allocations.first.staff_profile_id)
        .to eq(appointment.staff_profiles.first.id)
    end

    it "splits evenly between two therapists" do
      couples_service = create(:service, name: "Couples")
      couples = create(:service_variant, service: couples_service, duration_minutes: 60,
                                         therapist_count: 2, required_client_capacity: 2)
      w = build_world(rooms: { couple: 1 }, therapists: 2)
      w[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service: couples_service) }
      appt = complete(book(w, variant_ids: [ couples.id ]))
      o = Sales::OpenOrder.call(appointment: appt)

      Sales::AllocateTips.call(order: o, amount_cents: 3_000)
      expect(o.tip_allocations.pluck(:amount_cents)).to contain_exactly(1_500, 1_500)
    end

    it "gives an odd remainder to the primary therapist rather than losing it" do
      couples_service = create(:service, name: "Couples")
      couples = create(:service_variant, service: couples_service, duration_minutes: 60,
                                         therapist_count: 2, required_client_capacity: 2)
      w = build_world(rooms: { couple: 1 }, therapists: 2)
      w[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service: couples_service) }
      o = Sales::OpenOrder.call(appointment: complete(book(w, variant_ids: [ couples.id ])))

      Sales::AllocateTips.call(order: o, amount_cents: 3_001)
      expect(o.tip_allocations.sum(:amount_cents)).to eq(3_001)
    end

    it "rejects a manual split that does not sum to the tip" do
      staff = appointment.staff_profiles.first
      expect {
        Sales::AllocateTips.call(order:, amount_cents: 2_000,
                                 allocations: [ { staff_profile_id: staff.id, amount_cents: 1_000 } ])
      }.to raise_error(Sales::AllocateTips::Invalid, /sum to the tip/)
    end
  end

  describe "settlement (BR-22)" do
    it "refuses to settle while anything is outstanding" do
      expect { Sales::SettleOrder.call(order:) }
        .to raise_error(Sales::SettleOrder::Unsettled)
    end

    it "settles when payments cover the total, and generates earnings" do
      Sales::RecordPayment.call(order:, method: "card", amount_cents: order.total_cents)
      Sales::SettleOrder.call(order:)

      expect(order.reload.status).to eq("paid")
      expect(EarningLine.where(appointment_id: appointment.id, source: "session")).to be_present
    end
  end

  # BR-19 in its Release 1 form: recorded as owed, never charged.
  describe "cancellation and no-show fees" do
    it "writes an open Fee order for a no-show, and charges nothing" do
      appt = book(world)
      Scheduling::TransitionStatus.call(appointment: appt, to: "no_show")

      fee = Order.find_by(appointment_id: appt.id, kind: "fee")
      expect(fee).to be_present
      expect(fee.status).to eq("open")               # owed, not collected
      expect(fee.payments).to be_empty
      expect(fee.total_cents).to eq((appt.reload.total_price_cents * 0.2).round)
      expect(fee.order_line_items.first.revenue_category).to eq("fee")
    end

    it "charges nothing for a cancellation outside the 4-hour window" do
      # Same day as the seeded shift; the window is measured from starts_at.
      appt = book(world, start_at: world[:at] + 3.hours)
      Scheduling::TransitionStatus.call(appointment: appt, to: "cancelled")

      expect(appt.reload.fee_charged_cents).to be_zero
      expect(Order.where(appointment_id: appt.id, kind: "fee")).to be_empty
    end
  end
end
