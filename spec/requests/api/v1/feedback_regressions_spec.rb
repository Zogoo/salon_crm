require "rails_helper"

RSpec.describe "Feedback regressions", type: :request do
  let(:world) { build_world(rooms: { single: 2, couple: 1 }, therapists: 3) }
  let(:owner) { create(:user, role: "owner") }
  let(:headers) { auth_headers(owner) }

  def json = JSON.parse(response.body)

  %w[cancelled late_cancelled].each do |status|
    it "hides #{status} from the calendar while preserving client history" do
      old = book(world)
      old.update!(status: status)
      old.appointment_staff.update_all(status: status)
      replacement = book(world, room_id: old.room_id)
      get "/api/v1/appointments/calendar", params: { location_id: world[:location].id, date: world[:date] }, headers: headers
      expect(json.fetch("appointments").pluck("id")).to eq([ replacement.id ])
      get "/api/v1/clients/#{world[:client].id}/appointments", headers: headers
      expect(json.fetch("appointments").pluck("id")).to include(old.id, replacement.id)
    end
  end

  it "keeps a no-show on the calendar, where it does not block the slot" do
    no_show = book(world)
    no_show.update!(status: "no_show")
    no_show.appointment_staff.update_all(status: "no_show")
    replacement = book(world, room_id: no_show.room_id)
    get "/api/v1/appointments/calendar", params: { location_id: world[:location].id, date: world[:date] }, headers: headers
    expect(json.fetch("appointments").map { |a| [ a["id"], a["status"] ] })
      .to contain_exactly([ no_show.id, "no_show" ], [ replacement.id, "scheduled" ])
  end

  it "generates session earnings at completion, and settlement does not duplicate them" do
    appt = book(world)
    %w[checked_in in_progress].each do |to|
      post "/api/v1/appointments/#{appt.id}/transition",
           params: { to: }, headers:, as: :json
      expect(EarningLine.where(appointment: appt)).to be_empty
    end

    post "/api/v1/appointments/#{appt.id}/transition",
         params: { to: "completed" }, headers:, as: :json

    expect(response).to have_http_status(:ok)
    expect(EarningLine.where(appointment: appt, source: "session").sum(:amount_cents)).to eq(4500)

    order = Sales::OpenOrder.call(appointment: appt.reload)
    Sales::RecordPayment.call(order:, method: "cash", amount_cents: order.total_cents, actor: owner)
    expect { 2.times { Sales::SettleOrder.call(order:, actor: owner) } }.not_to change(EarningLine, :count)
  end

  it "serializes feedback for the correct client's appointments" do
    appt = book(world)
    rating = Crm::RecordRating.call(appointment: appt, score: 9, channel: "kiosk", feedback: "Great session")
    get "/api/v1/clients/#{world[:client].id}/ratings", headers: headers
    expect(response).to have_http_status(:ok)
    expect(json.fetch("ratings").first).to include("appointment_id" => appt.id, "score" => 9, "comment" => rating.feedback)
    get "/api/v1/clients/#{create(:client).id}/ratings", headers: headers
    expect(json.fetch("ratings")).to be_empty
  end

  it "shows purchased gift cards, including value and remaining balance, only for their buyer" do
    card = GiftCards::IssueCard.call(location: world[:location], amount_cents: 10000, payment_method: "cash",
                                    buyer_client: world[:client], actor: owner)
    get "/api/v1/clients/#{world[:client].id}/gift_cards", headers: headers
    expect(response).to have_http_status(:ok)
    expect(json.fetch("gift_cards").first).to include("code" => card.code, "initial_value_cents" => 10000, "balance_cents" => 10000)
    get "/api/v1/clients/#{create(:client).id}/gift_cards", headers: headers
    expect(json.fetch("gift_cards")).to be_empty
  end

  %w[ratings gift_cards].each do |endpoint|
    it "protects client #{endpoint} from unauthenticated and therapist access" do
      path = "/api/v1/clients/#{world[:client].id}/#{endpoint}"
      get path
      expect(response).to have_http_status(:unauthorized)
      get path, headers: auth_headers(world[:staff].first.user)
      expect(response).to have_http_status(:forbidden)
      get "/api/v1/clients/0/#{endpoint}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
