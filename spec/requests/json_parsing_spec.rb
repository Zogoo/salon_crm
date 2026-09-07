require "rails_helper"

# Regression guard for a whole class of bug the rest of the suite cannot see.
#
# The generated specs post `params: {...}`, which Rails sends form-encoded.
# Real clients send `Content-Type: application/json`, which goes through
# ActionDispatch's parameter parser and `ActiveSupport::JSON.decode`. When the
# `json` gem released 3.0 it made `JSON.parse` keyword-only while ActiveSupport
# still passed its options hash positionally, so under Ruby 3.4 every JSON
# request returned 400 — and the entire suite stayed green, because none of it
# sent JSON.
#
# These examples send a real JSON body. If the parser breaks again, they fail.
RSpec.describe "JSON request parsing", type: :request do
  let!(:user) do
    create(:user, email: "json@example.com", password: "password123",
                  password_confirmation: "password123")
  end

  it "parses a JSON request body" do
    post "/api/v1/auth/sign_in",
         params: { email: "json@example.com", password: "password123" },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("token")
  end

  it "parses a nested JSON body" do
    token = Auth::JwtService.encode(user)
    post "/api/v1/clients",
         params: { client: { first_name: "Json", last_name: "Body", phone: "+13125559999" } },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    # 403 would mean the role check ran, which still proves the body parsed.
    expect(response.status).not_to eq(400),
      "a JSON body failed to parse — see ActiveSupport::JSON.decode and the json gem pin"
  end

  it "decodes JSON through ActiveSupport, which is what the parser uses" do
    expect(ActiveSupport::JSON.decode('{"a":1}')).to eq("a" => 1)
  end
end
