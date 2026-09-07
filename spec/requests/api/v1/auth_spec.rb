require "rails_helper"

RSpec.describe "Api::V1::Auth", type: :request do
  describe "POST /api/v1/auth/sign_up" do
    let(:params) do
      { email: "new@example.com", password: "password123",
        password_confirmation: "password123", name: "New User" }
    end

    it "creates a user and returns a token" do
      expect {
        post "/api/v1/auth/sign_up", params: params
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("token")
      expect(response.parsed_body["user"]).to include("email" => "new@example.com")
    end

    it "rejects invalid input" do
      post "/api/v1/auth/sign_up", params: params.merge(email: "bad")
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/auth/sign_in" do
    let!(:user) { create(:user, email: "member@example.com", password: "password123", password_confirmation: "password123") }

    it "returns a token for valid credentials" do
      post "/api/v1/auth/sign_in", params: { email: "member@example.com", password: "password123" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("token")
    end

    it "rejects invalid credentials" do
      post "/api/v1/auth/sign_in", params: { email: "member@example.com", password: "wrong" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/auth/me" do
    let(:user) { create(:user) }

    it "returns the current user with a valid token" do
      get "/api/v1/auth/me", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("email" => user.email)
    end

    it "rejects a missing token" do
      get "/api/v1/auth/me"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
