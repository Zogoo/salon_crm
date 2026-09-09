require "rails_helper"

# Doc 05 §"Money" and §"Membership". BR-23, BR-39a, BR-41, BR-45a, BR-48.
RSpec.describe "Money and membership administration API", type: :request do
  let(:world)   { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner)   { create(:user, email: "mo-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "mo-mgr@example.com", role: "manager", location: world[:location]) }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  def completed_order
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    Sales::OpenOrder.call(appointment: appt.reload, actor: owner)
  end

  describe "refunds (BR-23)" do
    it "returns money as a refund row and leaves the payment intact" do
      order = completed_order
      Sales::RecordPayment.call(order:, method: "card", amount_cents: 5000, actor: owner)
      payment = order.payments.captured.first

      post "/api/v1/orders/#{order.id}/refunds",
           params: { payment_id: payment.id, amount_cents: 2000, reason: "owner_discretion" },
           headers: auth(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(payment.reload.amount_cents).to eq(5000)
      expect(payment.status).to eq("captured")
      expect(Refund.where(payment:).sum(:amount_cents)).to eq(2000)
    end

    it "refuses to refund more than was captured" do
      order = completed_order
      Sales::RecordPayment.call(order:, method: "card", amount_cents: 5000, actor: owner)
      payment = order.payments.captured.first

      post "/api/v1/orders/#{order.id}/refunds",
           params: { payment_id: payment.id, amount_cents: 9000 },
           headers: auth(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("refund_exceeds_payment")
      expect(Refund.count).to eq(0)
    end
  end

  describe "manual lines (BR-48)" do
    it "requires a revenue category so reporting cannot mis-file it" do
      order = completed_order

      post "/api/v1/orders/#{order.id}/line_items",
           params: { description: "Retail oil", unit_price_cents: 2500 },
           headers: auth(owner), as: :json
      expect(response).to have_http_status(:bad_request)

      post "/api/v1/orders/#{order.id}/line_items",
           params: { description: "Retail oil", unit_price_cents: 2500, quantity: 2,
                     revenue_category: "service" },
           headers: auth(owner), as: :json
      expect(response).to have_http_status(:created)
      # quantity x unit price lands in the subtotal.
      expect(order.reload.order_line_items.where(description: "Retail oil").sum(:line_total_cents))
        .to eq(5000)
    end
  end

  describe "membership credits" do
    let(:membership) do
      Memberships::Enrol.call(client: world[:client], location: world[:location],
                              default_service_variant_id: world[:variant].id, actor: owner)
    end

    it "exposes the ledger behind the balance (BR-41)" do
      membership.update!(credits_balance: 2)

      get "/api/v1/memberships/#{membership.id}/credits", headers: auth(owner)

      expect(response).to have_http_status(:ok)
      expect(json["credits_balance"]).to eq(2)
      expect(json).to have_key("transactions")
    end

    # BR-39a: the override is the Owner's or Manager's, and it is recorded.
    it "records the approver when a credit is redeemed away from home" do
      # The member enrolled at world[:location] and is visiting `other`; the
      # approver is the Manager on duty there, not at the home location.
      other = create(:location, code: "away#{SecureRandom.hex(2)}")
      away_manager = create(:user, email: "away-mgr@example.com", role: "manager", location: other)
      membership.update!(credits_balance: 1)
      order = completed_order
      order.update!(location: other)

      post "/api/v1/memberships/#{membership.id}/authorize_cross_location",
           params: { order_id: order.id }, headers: auth(away_manager), as: :json

      expect(response).to have_http_status(:ok)
      txn = membership.membership_credit_transactions.find_by(kind: "redeem")
      expect(txn.cross_location_approved_by_user_id).to eq(away_manager.id)
    end
  end

  describe "rating alerts (BR-45a)" do
    it "lists only ratings below the location's threshold" do
      appt = book(world)
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
      Crm::RecordRating.call(appointment: appt.reload, score: 3, channel: "kiosk",
                             feedback: "Too cold")

      get "/api/v1/reports/ratings/alerts",
          params: { location_id: world[:location].id }, headers: auth(manager)

      expect(response).to have_http_status(:ok)
      expect(json["alerts"].map { |a| a["score"] }).to eq([ 3 ])
    end
  end
end
