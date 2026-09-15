require "rails_helper"

# Doc 05 §"staff_requests" and BR-05/BR-06.
RSpec.describe "Staff requests API", type: :request do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "sr-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "sr-mgr@example.com", role: "manager", location: world[:location]) }
  let(:therapist) { world[:staff].first }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  # build_world already publishes the shift the therapist is booked against.
  let(:shift) { Shift.published.find_by!(staff_profile: therapist) }

  it "records the reviewer's note under the name it is read back as" do
    post "/api/v1/staff_requests",
         params: { kind: "shift_change", shift_id: shift.id,
                   requested_payload: { "ends_at" => "18:00" }, note: "finish early" },
         headers: auth(therapist.user), as: :json
    expect(response).to have_http_status(:created)
    id = json["id"]

    # The response calls it `review_note`, so that is what a caller sends back.
    # Reading only `note` silently dropped it — and `note` is already the
    # requester's own note, which the reviewer is not overwriting.
    post "/api/v1/staff_requests/#{id}/approve",
         params: { review_note: "agreed" }, headers: auth(owner), as: :json

    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("approved")
    expect(json["review_note"]).to eq("agreed")
  end

  # BR-06: the one approval the Owner withheld from Managers.
  it "refuses a location change approved by a Manager, with its own code" do
    post "/api/v1/staff_requests",
         params: { kind: "location_change", requested_payload: { "location_id" => create(:location).id } },
         headers: auth(therapist.user), as: :json
    id = json["id"]

    post "/api/v1/staff_requests/#{id}/approve", headers: auth(manager), as: :json

    expect(response).to have_http_status(:forbidden)
    expect(json.dig("error", "code")).to eq("owner_approval_required")
    expect(StaffRequest.find(id).status).to eq("submitted")
  end

  it "refuses a request that points at nothing the reviewer can act on" do
    other_shift = Shift.published.find_by!(staff_profile: world[:staff].last)
    post "/api/v1/staff_requests", params: { kind: "shift_change", shift_id: other_shift.id },
                                   headers: auth(therapist.user), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("shift_required")

    post "/api/v1/staff_requests",
         params: { kind: "location_change", requested_payload: { "location_id" => therapist.location_id } },
         headers: auth(therapist.user), as: :json
    expect(json.dig("error", "code")).to eq("location_required")
  end

  it "describes the shift and the destination in words" do
    destination = create(:location, name: "Riverside")
    post "/api/v1/staff_requests",
         params: { kind: "location_change", requested_payload: { "location_id" => destination.id } },
         headers: auth(therapist.user), as: :json
    expect(json["requested_location"]).to eq({ "id" => destination.id, "name" => "Riverside" })

    post "/api/v1/staff_requests",
         params: { kind: "shift_change", shift_id: shift.id, requested_payload: { "ends_at" => "18:00" } },
         headers: auth(therapist.user), as: :json
    expect(json["shift"]).to include("starts_at" => "09:00", "ends_at" => "22:00")
  end

  it "pages the list and filters by several statuses at once, so a reviewer starts on what is waiting" do
    waiting = StaffRequest.create!(staff_profile: therapist, kind: "shift_change", shift:,
                                   status: "submitted", requested_payload: {})
    StaffRequest.create!(staff_profile: therapist, kind: "shift_change", shift:,
                         status: "approved", requested_payload: {})
    StaffRequest.create!(staff_profile: therapist, kind: "shift_change", shift:,
                         status: "withdrawn", requested_payload: {})

    get "/api/v1/staff_requests", params: { status: "submitted", limit: 1 }, headers: auth(owner)
    expect(json["staff_requests"].map { |r| r["id"] }).to eq([ waiting.id ])
    expect(json["meta"]).to include("count" => 1, "page" => 1, "limit" => 1)

    get "/api/v1/staff_requests", params: { status: "approved,rejected" }, headers: auth(owner)
    expect(json["staff_requests"].map { |r| r["status"] }).to eq([ "approved" ])
  end
end
