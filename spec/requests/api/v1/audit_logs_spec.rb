require "rails_helper"

RSpec.describe "Audit log API", type: :request do
  let(:owner) { create(:user, role: "owner") }
  let(:client) { create(:client) }

  before do
    AuditLog.record!(auditable: client, action: "client.updated", actor: owner,
                     changes: { phone: [ "old", "new" ] })
  end

  it "lets the owner filter and paginate the audit trail" do
    get "/api/v1/audit_logs", params: { audit_action: "client", auditable_type: "Client" },
                              headers: auth_headers(owner)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("audit_logs").first).to include(
      "action" => "client.updated", "auditable_type" => "Client", "auditable_id" => client.id
    )
  end

  it "filters on actions containing an underscore, and treats it literally" do
    AuditLog.record!(auditable: client, action: "care_notes.read", actor: owner)
    AuditLog.record!(auditable: client, action: "careXnotes.read", actor: owner)

    get "/api/v1/audit_logs", params: { audit_action: "care_notes" }, headers: auth_headers(owner)

    expect(JSON.parse(response.body).fetch("audit_logs").map { |l| l["action"] }).to eq([ "care_notes.read" ])
  end

  it "rejects unauthenticated, manager and staff access" do
    get "/api/v1/audit_logs"
    expect(response).to have_http_status(:unauthorized)

    location = create(:location)
    %w[manager staff].each do |role|
      get "/api/v1/audit_logs", headers: auth_headers(create(:user, role:, location:))
      expect(response).to have_http_status(:forbidden)
    end
  end
end
