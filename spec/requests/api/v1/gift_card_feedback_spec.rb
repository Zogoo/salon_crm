require "rails_helper"

RSpec.describe "Gift-card issuance feedback", type: :request do
  let(:world) { build_world }
  let(:owner) { create(:user, role: "owner") }
  let(:payload) do
    { gift_card: { location_id: world[:location].id, amount_cents: 10000, payment_method: "cash",
                   code: " 00123abc ", buyer_client_id: world[:client].id } }
  end

  it "preserves leading zeros, normalizes a custom code and links the purchaser" do
    post "/api/v1/gift_cards", params: payload, headers: auth_headers(owner), as: :json
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to include("code" => "00123ABC")
    expect(GiftCard.last.buyer_client).to eq(world[:client])
  end

  it "generates a code when the input is blank" do
    payload[:gift_card][:code] = "  "
    post "/api/v1/gift_cards", params: payload, headers: auth_headers(owner), as: :json
    expect(response).to have_http_status(:created)
    expect(GiftCard.last.code).to start_with("GC-")
  end

  it "does not create a second card, order or payment when the code is already taken" do
    post "/api/v1/gift_cards", params: payload, headers: auth_headers(owner), as: :json
    counts = [ GiftCard.count, Order.count, Payment.count, GiftCardTransaction.count ]
    post "/api/v1/gift_cards", params: payload, headers: auth_headers(owner), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error").join).to include("Code has already been taken")
    expect([ GiftCard.count, Order.count, Payment.count, GiftCardTransaction.count ]).to eq(counts)
  end

  it "rejects an unknown purchaser instead of silently losing the profile link" do
    payload[:gift_card][:buyer_client_id] = 0
    expect {
      post "/api/v1/gift_cards", params: payload, headers: auth_headers(owner), as: :json
    }.not_to change(GiftCard, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects unauthenticated users, staff and a manager selling at another location" do
    post "/api/v1/gift_cards", params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/gift_cards", params: payload, headers: auth_headers(world[:staff].first.user), as: :json
    expect(response).to have_http_status(:forbidden)
    manager = create(:user, role: "manager", location: create(:location))
    post "/api/v1/gift_cards", params: payload, headers: auth_headers(manager), as: :json
    expect(response).to have_http_status(:not_found)
    expect(GiftCard.count).to eq(0)
  end
end
