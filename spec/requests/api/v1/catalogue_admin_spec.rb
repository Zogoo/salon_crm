require "rails_helper"

# Doc 05 §5 and FRS §19: the Owner's service menu and price list.
RSpec.describe "Catalogue administration API", type: :request do
  let(:world)   { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner)   { create(:user, email: "cat-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "cat-mgr@example.com", role: "manager", location: world[:location]) }
  let(:service) { world[:service] }
  let(:variant) { world[:variant] }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  describe "pricing" do
    # BR-11 snapshots price at booking; invariant 5 keeps the history intact.
    it "opens a new price period instead of rewriting the old one" do
      post "/api/v1/service_variants/#{variant.id}/prices",
           params: { location_id: world[:location].id, price_cents: 12_000,
                     effective_from: "2026-07-01" },
           headers: auth(owner), as: :json
      expect(response).to have_http_status(:created)

      old_price = Catalogue::ResolvePrice.call(variant:, location: world[:location], on: Date.new(2026, 3, 1))
      new_price = Catalogue::ResolvePrice.call(variant:, location: world[:location], on: Date.new(2026, 8, 1))
      expect(new_price).to eq(12_000)
      expect(old_price).not_to eq(12_000)
    end

    it "does not change what an already-booked appointment was sold for" do
      appointment = book(world)
      sold_for = appointment.total_price_cents

      post "/api/v1/service_variants/#{variant.id}/prices",
           params: { location_id: world[:location].id, price_cents: 99_900,
                     effective_from: world[:at].to_date.to_s },
           headers: auth(owner), as: :json

      expect(appointment.reload.total_price_cents).to eq(sold_for)
    end

    it "keeps the price list away from a Manager" do
      get "/api/v1/service_variants/#{variant.id}/prices", headers: auth(manager)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the menu" do
    it "deactivates rather than deletes a service with history" do
      book(world) # gives the variant appointment history

      delete "/api/v1/services/#{service.id}", headers: auth(owner)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("service_in_use")

      post "/api/v1/services/#{service.id}/deactivate", headers: auth(owner), as: :json
      expect(response).to have_http_status(:ok)
      expect(service.reload.active).to be(false)
    end

    it "lets the Owner add a service and a variant" do
      post "/api/v1/services",
           params: { service: { name: "Hot Stone", kind: "standard",
                                service_category_id: service.service_category_id } },
           headers: auth(owner), as: :json
      expect(response).to have_http_status(:created)
      new_id = json["id"]

      post "/api/v1/services/#{new_id}/service_variants",
           params: { service_variant: { duration_minutes: 90, therapist_count: 1,
                                        required_client_capacity: 1 } },
           headers: auth(owner), as: :json
      expect(response).to have_http_status(:created)
      expect(json["duration_minutes"]).to eq(90)
    end

    # A duration off the ladder produces an unpayable earning line (BR-33).
    it "refuses a variant duration that is not on the pay ladder" do
      post "/api/v1/services/#{service.id}/service_variants",
           params: { service_variant: { duration_minutes: 55, therapist_count: 1,
                                        required_client_capacity: 1 } },
           headers: auth(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses menu edits from a Manager" do
      patch "/api/v1/services/#{service.id}",
            params: { service: { name: "Renamed" } }, headers: auth(manager), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(service.reload.name).not_to eq("Renamed")
    end
  end
end
