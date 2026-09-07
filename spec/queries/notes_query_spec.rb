require "rails_helper"

RSpec.describe NotesQuery do
  let(:user) { create(:user) }

  it "returns the user's notes most-recent first" do
    old = create(:note, user: user, created_at: 2.days.ago)
    fresh = create(:note, user: user, created_at: 1.hour.ago)
    expect(described_class.new(user.notes).call.to_a).to eq([ fresh, old ])
  end

  it "filters by a case-insensitive search term" do
    match = create(:note, user: user, title: "Groceries")
    create(:note, user: user, title: "Homework")
    results = described_class.new(user.notes).call(search: "grocer")
    expect(results).to contain_exactly(match)
  end

  it "treats LIKE wildcards in the term literally" do
    create(:note, user: user, title: "100% done")
    create(:note, user: user, title: "anything")
    results = described_class.new(user.notes).call(search: "100%")
    expect(results.map(&:title)).to eq([ "100% done" ])
  end
end
