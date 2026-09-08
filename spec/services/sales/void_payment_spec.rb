require "rails_helper"

# BR-23. Payments are immutable, so voiding is the only correction available —
# without it a mis-keyed amount at the till could never be fixed.
RSpec.describe Sales::VoidPayment do
  let(:world) { build_world(rooms: { single: 1 }) }
  let(:owner) { create(:user, email: "vp-owner@example.com", role: "owner") }

  let(:order) do
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    Sales::OpenOrder.call(appointment: appt.reload)
  end

  it "voids a payment and puts the money back as outstanding" do
    payment = Sales::RecordPayment.call(order:, method: "cash", amount_cents: order.total_cents, actor: owner)
    Sales::SettleOrder.call(order:, actor: owner)
    expect(order.reload.status).to eq("paid")

    described_class.call(payment:, actor: owner, reason: "keyed the wrong amount")

    expect(payment.reload.status).to eq("voided")
    expect(payment.void_reason).to eq("keyed the wrong amount")
    # Reopened: somebody still has to take that money.
    expect(order.reload.status).to eq("open")
    expect(order.outstanding_cents).to eq(order.total_cents)
    expect(order.paid_cents).to be_zero
  end

  it "audit-logs the void, since this is how money would disappear" do
    payment = Sales::RecordPayment.call(order:, method: "card", amount_cents: 1_000, actor: owner)

    expect { described_class.call(payment:, actor: owner, reason: "duplicate") }
      .to change { AuditLog.where(action: "payment.voided").count }.by(1)

    log = AuditLog.where(action: "payment.voided").last
    expect(log.actor_user_id).to eq(owner.id)
    expect(log.changes_json["amount_cents"]).to eq(1_000)
  end

  it "insists on a reason" do
    payment = Sales::RecordPayment.call(order:, method: "cash", amount_cents: 500, actor: owner)
    expect { described_class.call(payment:, actor: owner, reason: "") }
      .to raise_error(described_class::Invalid, "reason_required")
  end

  it "refuses to void the same payment twice" do
    payment = Sales::RecordPayment.call(order:, method: "cash", amount_cents: 500, actor: owner)
    described_class.call(payment:, actor: owner, reason: "wrong")

    expect { described_class.call(payment: payment.reload, actor: owner, reason: "again") }
      .to raise_error(described_class::Invalid, "already_voided")
  end

  it "lets the corrected amount be recorded afterwards" do
    payment = Sales::RecordPayment.call(order:, method: "cash", amount_cents: order.total_cents, actor: owner)
    described_class.call(payment:, actor: owner, reason: "wrong method")

    expect {
      Sales::RecordPayment.call(order: order.reload, method: "card",
                                amount_cents: order.total_cents, actor: owner)
    }.not_to raise_error
    expect(order.reload.outstanding_cents).to be_zero
  end
end
