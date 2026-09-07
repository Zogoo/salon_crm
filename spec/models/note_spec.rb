require "rails_helper"

RSpec.describe Note, type: :model do
  it { is_expected.to belong_to(:user) }

  it "is valid with a title and user" do
    expect(build(:note)).to be_valid
  end

  it "requires a title" do
    note = build(:note, title: nil)
    expect(note).not_to be_valid
  end

  it "is destroyed when its user is destroyed" do
    note = create(:note)
    expect { note.user.destroy }.to change(Note, :count).by(-1)
  end
end
