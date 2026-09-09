require "rails_helper"

# Doc 05 §6 and doc 01 §3.1. The Owner's staff administration surface.
RSpec.describe "Workforce administration API", type: :request do
  let(:world)   { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner)   { create(:user, email: "wf-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "wf-mgr@example.com", role: "manager", location: world[:location]) }
  let(:therapist) { world[:staff].first }
  let(:service) { Service.first }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  def ladder(cents = 4500)
    ServiceVariant::LADDER.map { |d| { duration_minutes: d, rate_cents: cents } }
  end

  describe "onboarding" do
    it "creates login, profile, qualifications and ladder in one call" do
      post "/api/v1/staff",
           params: { staff: { email: "new.therapist@example.com", display_name: "Nomin",
                              location_id: world[:location].id, service_ids: [ service.id ],
                              session_rates: ladder, rates_effective_from: "2026-01-01" } },
           headers: auth(owner), as: :json

      expect(response).to have_http_status(:created)
      profile = StaffProfile.find(json["id"])
      expect(profile.user.email).to eq("new.therapist@example.com")
      expect(profile.qualified_for?([ service.id ])).to be(true)
      # BR-01: schedulable means a location AND a qualification.
      expect(profile.location_id).to eq(world[:location].id)
      expect(profile.rate_cents_for(60, on: Date.new(2026, 6, 1))).to eq(4500)
    end

    it "refuses to onboard staff as anyone but the Owner" do
      post "/api/v1/staff",
           params: { staff: { email: "x@example.com", display_name: "X",
                              location_id: world[:location].id } },
           headers: auth(manager), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(User.find_by(email: "x@example.com")).to be_nil
    end
  end

  describe "session rates" do
    # build_world opens a ladder at 2026-01-01 (60 min = 4500), so a raise
    # mid-year has a real open period to close.
    it "closes the open period instead of rewriting history" do
      post "/api/v1/staff/#{therapist.id}/session_rates",
           params: { effective_from: "2026-07-01", rates: ladder(5000), note: "Review" },
           headers: auth(owner), as: :json
      expect(response).to have_http_status(:created)

      # BR-35: a session delivered in March is still paid at the March rate.
      expect(therapist.rate_cents_for(60, on: Date.new(2026, 3, 1))).to eq(4500)
      expect(therapist.rate_cents_for(60, on: Date.new(2026, 8, 1))).to eq(5000)
    end

    it "rejects a partial ladder rather than leaving a gap" do
      post "/api/v1/staff/#{therapist.id}/session_rates",
           params: { effective_from: "2026-07-01",
                     rates: [ { duration_minutes: 60, rate_cents: 4000 } ] },
           headers: auth(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("ladder_incomplete")
      # Nothing written, and the ladder in force is untouched.
      expect(therapist.staff_session_rates.where(effective_from: "2026-07-01")).to be_empty
      expect(therapist.rate_cents_for(60, on: Date.new(2026, 8, 1))).to eq(4500)
    end

    # BR-02/BR-03: rates are a security boundary, not a UI concern.
    it "never shows a Manager anyone's rates" do
      get "/api/v1/staff/#{therapist.id}/session_rates", headers: auth(manager)
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/staff/#{therapist.id}", headers: auth(manager)
      expect(json).not_to have_key("session_rates")
    end

    it "lets a therapist read their own ladder but not set it" do
      get "/api/v1/staff/#{therapist.id}/session_rates", headers: auth(therapist.user)
      expect(response).to have_http_status(:ok)

      post "/api/v1/staff/#{therapist.id}/session_rates",
           params: { effective_from: "2026-07-01", rates: ladder(99_999) },
           headers: auth(therapist.user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "qualifications" do
    it "replaces the set and refuses to leave a therapist unschedulable" do
      put "/api/v1/staff/#{therapist.id}/qualifications",
          params: { service_ids: [ service.id ] }, headers: auth(owner), as: :json
      expect(json["qualifications"].map { |q| q["service_id"] }).to eq([ service.id ])

      put "/api/v1/staff/#{therapist.id}/qualifications",
          params: { service_ids: [] }, headers: auth(owner), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(therapist.reload.staff_qualifications).not_to be_empty
    end
  end

  describe "monthly rate (BR-36)" do
    it "is refused for a therapist, who is paid per session" do
      post "/api/v1/staff/#{therapist.id}/monthly_rate",
           params: { amount_cents: 500_000, effective_from: "2026-01-01" },
           headers: auth(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("not_a_manager")
    end
  end
end
