require "rails_helper"

RSpec.describe AuditLogsQuery do
  let(:owner) { create(:user, role: "owner") }
  let(:client) { create(:client) }

  before do
    AuditLog.record!(auditable: client, action: "client.updated", actor: owner,
                     changes: { first_name: [ "Old", "New" ] })
    AuditLog.record!(auditable: owner, action: "profile.updated", actor: owner)
  end

  it "filters safely by partial action, resource type and actor" do
    rows = described_class.new(AuditLog.all, action: "client", auditable_type: "Client",
                                             actor_user_id: owner.id).call
    expect(rows.pluck(:action)).to eq([ "client.updated" ])
  end

  it "escapes LIKE wildcards instead of treating them as filters" do
    expect(described_class.new(AuditLog.all, action: "%").call).to be_empty
  end
end
