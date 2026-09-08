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
         params: { kind: "location_change", requested_payload: { "location" => "Luma" } },
         headers: auth(therapist.user), as: :json
    id = json["id"]

    post "/api/v1/staff_requests/#{id}/approve", headers: auth(manager), as: :json

    expect(response).to have_http_status(:forbidden)
    expect(json.dig("error", "code")).to eq("owner_approval_required")
    expect(StaffRequest.find(id).status).to eq("submitted")
  end
end
