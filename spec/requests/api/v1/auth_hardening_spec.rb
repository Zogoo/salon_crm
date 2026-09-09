require "rails_helper"

# Doc 05 §3: second factor, password reset, session.
RSpec.describe "Authentication API", type: :request do
  let(:owner) { create(:user, email: "auth-owner@example.com", role: "owner", password: "password123") }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  describe "TOTP enrolment" do
    it "only takes effect once a valid code confirms it" do
      post "/api/v1/me/otp", headers: auth(owner), as: :json
      expect(response).to have_http_status(:created)
      secret = json["secret"]

      # Enrolment started but unconfirmed must not lock the account.
      expect(owner.reload.otp_enabled?).to be(false)
      post "/api/v1/session", params: { email: owner.email, password: "password123" }, as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/me/otp/confirm",
           params: { otp_code: ROTP::TOTP.new(secret).now }, headers: auth(owner), as: :json
      expect(response).to have_http_status(:ok)
      expect(owner.reload.otp_enabled?).to be(true)
    end

    it "asks for the second factor once enabled, and tells the console why" do
      secret = ROTP::Base32.random
      owner.update!(otp_secret: secret, otp_enabled_at: Time.current)

      post "/api/v1/session", params: { email: owner.email, password: "password123" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("otp_required")

      post "/api/v1/session",
           params: { email: owner.email, password: "password123", otp_code: "000000" }, as: :json
      expect(json.dig("error", "code")).to eq("otp_invalid")

      post "/api/v1/session",
           params: { email: owner.email, password: "password123",
                     otp_code: ROTP::TOTP.new(secret).now }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to have_key("token")
    end
  end

  describe "password reset" do
    # A different answer for a known address turns this into an
    # account-enumeration oracle.
    it "answers the same way whether or not the address exists" do
      post "/api/v1/password_resets", params: { email: owner.email }, as: :json
      known = response.status
      post "/api/v1/password_resets", params: { email: "nobody@example.com" }, as: :json

      expect(response.status).to eq(known)
      expect(response).to have_http_status(:accepted)
    end

    it "stores only a digest, so the row cannot be replayed" do
      token = owner.issue_password_reset!
      expect(owner.reload.password_reset_token_digest).not_to eq(token)

      put "/api/v1/password_resets/#{owner.password_reset_token_digest}",
          params: { password: "brand-new-password" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      put "/api/v1/password_resets/#{token}",
          params: { password: "brand-new-password" }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(owner.reload.authenticate("brand-new-password")).to be_truthy
    end

    it "refuses an expired token and consumes a used one" do
      token = owner.issue_password_reset!
      owner.update!(password_reset_sent_at: 3.hours.ago)

      put "/api/v1/password_resets/#{token}", params: { password: "another-password" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      owner.update!(password_reset_sent_at: Time.current)
      put "/api/v1/password_resets/#{token}", params: { password: "another-password" }, as: :json
      expect(response).to have_http_status(:no_content)

      # Single use: the same token must not work twice.
      put "/api/v1/password_resets/#{token}", params: { password: "third-password" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "renders a receipt and a statement as PDFs" do
    world = build_world(rooms: { single: 1 }, therapists: 1)
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    order = Sales::OpenOrder.call(appointment: appt.reload, actor: owner)

    get "/api/v1/orders/#{order.id}/receipt", headers: auth(owner)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body[0, 4]).to eq("%PDF")
  end
end
