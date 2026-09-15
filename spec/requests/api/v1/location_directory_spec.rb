require "rails_helper"

RSpec.describe "Location directory", type: :request do
  let(:home) { create(:location, name: "Home") }
  let!(:other) { create(:location, name: "Elsewhere") }
  let(:therapist) do
    user = create(:user, role: "staff", email: "dir-staff@example.com")
    create(:staff_profile, user:, location: home)
    user
  end

  it "lists every active location by name, even to a therapist scoped to one" do
    get "/api/v1/locations/directory", headers: auth_headers(therapist)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["locations"]).to include({ "id" => other.id, "name" => "Elsewhere" })
    expect(JSON.parse(response.body)["locations"].first.keys).to contain_exactly("id", "name")
  end

  it "is not public" do
    get "/api/v1/locations/directory"
    expect(response).to have_http_status(:unauthorized)
  end
end
