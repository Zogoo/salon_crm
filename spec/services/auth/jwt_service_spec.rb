require "rails_helper"

RSpec.describe Auth::JwtService do
  let(:user) { create(:user) }

  it "round-trips a user id through encode/decode" do
    token = described_class.encode(user)
    payload = described_class.decode(token)
    expect(payload[:sub]).to eq(user.id)
    expect(payload[:email]).to eq(user.email)
  end

  it "raises on an expired token" do
    token = described_class.encode(user, expiry: -1.hour)
    expect { described_class.decode(token) }.to raise_error(JWT::ExpiredSignature)
  end

  it "raises on a tampered token" do
    expect { described_class.decode("not.a.jwt") }.to raise_error(JWT::DecodeError)
  end
end
