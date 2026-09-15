require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  it "is valid with default attributes" do
    expect(user).to be_valid
  end

  it { is_expected.to have_one_attached(:avatar) }

  it "requires a name" do
    user.name = nil
    expect(user).not_to be_valid
  end

  it "requires a well-formed email" do
    user.email = "not-an-email"
    expect(user).not_to be_valid
  end

  it "requires a unique, case-insensitive email" do
    create(:user, email: "dup@example.com")
    duplicate = build(:user, email: "DUP@example.com")
    expect(duplicate).not_to be_valid
  end

  it "downcases and strips the email" do
    user.email = "  MixedCase@Example.COM  "
    user.validate
    expect(user.email).to eq("mixedcase@example.com")
  end

  it "requires a password of at least 8 characters" do
    user.password = user.password_confirmation = "short"
    expect(user).not_to be_valid
  end

  it "authenticates with the correct password" do
    user.save!
    expect(user.authenticate("password123")).to eq(user)
    expect(user.authenticate("wrong")).to be_falsey
  end

  describe "avatar validation" do
    it "accepts an image avatar" do
      user.avatar.attach(io: StringIO.new("data"), filename: "a.png", content_type: "image/png")
      expect(user).to be_valid
    end

    it "rejects a non-image avatar" do
      user.avatar.attach(io: StringIO.new("data"), filename: "a.txt", content_type: "text/plain")
      expect(user).not_to be_valid
    end
  end
end
