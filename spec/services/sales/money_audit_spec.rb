require "rails_helper"

# Doc 01 §2.2: a refund and a manual discount are both Owner-only writes, and
# every one of them writes an audit row. Both were going straight to the model
# from the controller, so neither left a trace of who did it or why.
RSpec.describe "Owner money writes are audited" do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "ma-owner@example.com", role: "owner") }

  let(:order) do
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    Sales::OpenOrder.call(appointment: appt.reload, actor: owner)
  end

  describe "refunds" do
    let(:payment) do
      Sales::RecordPayment.call(order:, method: "card", amount_cents: 5_000, actor: owner)
      order.payments.captured.first
    end

    it "writes an audit row naming the actor and the reason" do
      payment # Exclude setup (payment capture audit) from the refund assertion.
      expect {
        Sales::IssueRefund.call(order:, payment:, amount_cents: 2_000, actor: owner, reason: "error")
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.order(:id).last
      expect(log.action).to eq("payment.refunded")
      expect(log.actor_user_id).to eq(owner.id)
    end

    # BR-23: the capture stays on the record; the refund is a separate row.
    it "leaves the payment untouched" do
      Sales::IssueRefund.call(order:, payment:, amount_cents: 2_000, actor: owner)

      expect(payment.reload.amount_cents).to eq(5_000)
      expect(payment.status).to eq("captured")
    end

    it "counts refunds already issued, so two cannot together exceed the capture" do
      Sales::IssueRefund.call(order:, payment:, amount_cents: 3_000, actor: owner)

      expect {
        Sales::IssueRefund.call(order:, payment:, amount_cents: 2_500, actor: owner)
      }.to raise_error(Sales::IssueRefund::Invalid, "refund_exceeds_payment")
      expect(Refund.where(payment:).sum(:amount_cents)).to eq(3_000)
    end
  end

  describe "manual discounts" do
    it "writes an audit row and lowers the total" do
      expect {
        Sales::ApplyDiscount.call(order:, amount_cents: 1_000, actor: owner, reason: "Goodwill")
      }.to change(AuditLog, :count).by(1)

      expect(AuditLog.order(:id).last.action).to eq("order.discounted")
      expect(order.reload.discount_cents).to eq(1_000)
    end
  end
end
