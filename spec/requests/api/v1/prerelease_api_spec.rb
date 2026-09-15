require "rails_helper"

# HTTP-level checks for the pre-release fixes: who may do what, and what the
# desk sees when a rule refuses.
RSpec.describe "Pre-release API", type: :request do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, role: "owner") }
  let(:manager) { create(:user, role: "manager", location: world[:location]) }

  def json = JSON.parse(response.body)

  describe "discounts" do
    let(:appt) { book(world) }
    let(:order_id) do
      post "/api/v1/orders", params: { order: { appointment_id: appt.id } }, headers: auth_headers(manager), as: :json
      json.fetch("id")
    end

    it "lets a Manager discount within the limit and explains a refusal above it" do
      post "/api/v1/orders/#{order_id}/discounts", params: { amount_cents: 1_600, reason: "Late start" },
                                                   headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:created)
      expect(json).to include("discount_cents" => 1_600, "manager_discount_limit_cents" => 1_600)

      post "/api/v1/orders/#{order_id}/discounts", params: { amount_cents: 100, reason: "More" },
                                                   headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("discount_above_manager_limit")
    end

    it "keeps therapists out" do
      post "/api/v1/orders/#{order_id}/discounts", params: { amount_cents: 100, reason: "x" },
                                                   headers: auth_headers(world[:staff].first.user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "deposits and one-step checkout" do
    it "records a deposit, shows it on the appointment and order, and checks out in one call" do
      appt = book(world)
      post "/api/v1/appointments/#{appt.id}/deposit", params: { amount_cents: 2_000, method: "zelle" },
                                                      headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:created)
      expect(json.fetch("deposit")).to include("amount_cents" => 2_000, "status" => "held", "method" => "zelle")

      post "/api/v1/appointments/#{appt.id}/complete_for_checkout", headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("appointment", "status")).to eq("completed")

      get "/api/v1/orders/#{json.fetch('order_id')}", headers: auth_headers(manager)
      expect(json).to include("deposit_cents" => 2_000, "outstanding_cents" => 6_000)
    end

    it "refuses one-step checkout before a therapist is assigned" do
      appt = book(world, provisional: true)
      post "/api/v1/appointments/#{appt.id}/complete_for_checkout", headers: auth_headers(manager), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("therapist_assignment_required")
    end

    it "refunds a held deposit at the desk" do
      appt = book(world)
      Sales::RecordDeposit.call(appointment: appt, amount_cents: 1_000, method: "cash", actor: manager)
      post "/api/v1/appointments/#{appt.id}/deposit/refund", params: { reason: "Client asked" },
                                                             headers: auth_headers(manager), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("deposit", "status")).to eq("refunded")
    end
  end

  it "reports a locked order as a clear 422 when the appointment is edited" do
    appt = book(world)
    order = Sales::OpenOrder.call(appointment: appt, actor: owner)
    Sales::RecordPayment.call(order:, method: "cash", amount_cents: 1_000, actor: owner)

    post "/api/v1/appointments/#{appt.id}/reschedule", params: { start_at: (world[:at] + 3.hours).iso8601 },
                                                       headers: auth_headers(manager), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("order_has_payments")
    expect(appt.reload.status).to eq("scheduled")
  end

  it "lists which dates made a repeat series fail" do
    appt = book(world, staff_profile_ids: [ world[:staff].first.id ])
    post "/api/v1/appointments/#{appt.id}/repeat", params: { interval_weeks: 1, count: 2 },
                                                   headers: auth_headers(manager), as: :json

    expect(response).to have_http_status(:conflict)
    expect(json.dig("error", "details", "dates").size).to eq(2)
    expect(json.dig("error", "message")).to include("No repeats were booked")
  end

  it "hides a provisional booking and its care notes from the therapist holding it" do
    appt = book(world, provisional: true)
    holder = appt.staff_profiles.first.user

    get "/api/v1/appointments/calendar", params: { location_id: world[:location].id, date: world[:date] },
                                         headers: auth_headers(holder)
    expect(json.fetch("appointments")).to be_empty
    get "/api/v1/care_notes", params: { appointment_id: appt.id }, headers: auth_headers(holder)
    expect(response).to have_http_status(:not_found)
  end

  it "drops requests for appointments no longer waiting from the Approvals list" do
    appt = book(world, requested_staff_profile_id: world[:staff].first.id)
    appt.update_columns(status: "cancelled")

    get "/api/v1/approval_requests", headers: auth_headers(manager)
    expect(json.fetch("approval_requests")).to be_empty
  end

  describe "service lengths in use" do
    it "refuses to change the shape of a length with upcoming bookings, but allows other edits" do
      book(world)
      patch "/api/v1/service_variants/#{world[:variant].id}",
            params: { service_variant: { duration_minutes: 90 } }, headers: auth_headers(owner), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("variant_in_use")

      patch "/api/v1/service_variants/#{world[:variant].id}",
            params: { service_variant: { active: false } }, headers: auth_headers(owner), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "audit log in salon time" do
    it "shows salon-local times and filters by the salon's business day" do
      world # the Owner's accessible locations come from here
      client = create(:client)
      # 01:30 UTC on the 10th is 20:30 Central on the 9th.
      travel_to(Time.utc(2026, 9, 10, 1, 30)) do
        AuditLog.record!(auditable: client, action: "client.updated", actor: owner)
      end

      get "/api/v1/audit_logs", params: { from: "2026-09-09", to: "2026-09-09" }, headers: auth_headers(owner)
      row = json.fetch("audit_logs").find { |l| l["auditable_id"] == client.id }
      expect(row.fetch("occurred_at")).to eq("2026-09-09T20:30:00-05:00")

      get "/api/v1/audit_logs", params: { from: "2026-09-10", to: "2026-09-10" }, headers: auth_headers(owner)
      expect(json.fetch("audit_logs").map { |l| l["auditable_id"] }).not_to include(client.id)
    end
  end
end
