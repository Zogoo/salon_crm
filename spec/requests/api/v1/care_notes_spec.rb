require "rails_helper"

# Doc 04 §5 and BR-44. Access is Owner, Manager, and the therapist on that
# appointment — and every read is audit-logged, because that is the only way to
# answer "who looked at this".
RSpec.describe "Care notes API", type: :request do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "cn-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "cn-mgr@example.com", role: "manager", location: world[:location]) }
  let(:appointment) { book(world) }
  let(:therapist) { appointment.staff_profiles.first }
  let(:stranger) { (world[:staff] - [ therapist ]).first }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  it "lets the assigned therapist write a note" do
    post "/api/v1/care_notes",
         params: { appointment_id: appointment.id, body: "Avoid the left knee" },
         headers: auth(therapist.user), as: :json

    expect(response).to have_http_status(:created)
    expect(json["author"]).to eq(therapist.display_name)
  end

  # This 500'd before the fix: AuditLog's changes column was NOT NULL, and Rails
  # writes NULL for the empty hash a read logs. Read logging is the whole point.
  it "logs every read, and the read still succeeds with no changes to record" do
    Crm::RecordCareNote.call(appointment:, staff_profile: therapist, body: "Note")

    expect {
      get "/api/v1/care_notes", params: { appointment_id: appointment.id },
          headers: auth(owner)
    }.to change { AuditLog.where(action: "care_notes.read").count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(json["care_notes"].first["body"]).to eq("Note")
  end

  it "returns times in the salon's zone, not UTC" do
    Crm::RecordCareNote.call(appointment:, staff_profile: therapist, body: "Note")
    get "/api/v1/care_notes", params: { appointment_id: appointment.id }, headers: auth(manager)

    # America/Chicago is -05:00 or -06:00; either way it is not a bare Z.
    expect(json["care_notes"].first["created_at"]).to match(/[+-]\d{2}:\d{2}\z/)
  end

  it "hides an appointment's notes from a therapist who is not on it" do
    Crm::RecordCareNote.call(appointment:, staff_profile: therapist, body: "Private")

    get "/api/v1/care_notes", params: { appointment_id: appointment.id },
        headers: auth(stranger.user)
    expect(response).to have_http_status(:not_found)

    post "/api/v1/care_notes",
         params: { appointment_id: appointment.id, body: "should not stick" },
         headers: auth(stranger.user), as: :json
    expect(response).to have_http_status(:not_found)
    expect(appointment.care_notes.count).to eq(1)
  end

  it "lets the Manager read but not write — writing is the therapist's job" do
    Crm::RecordCareNote.call(appointment:, staff_profile: therapist, body: "Note")

    get "/api/v1/care_notes", params: { appointment_id: appointment.id }, headers: auth(manager)
    expect(response).to have_http_status(:ok)

    post "/api/v1/care_notes",
         params: { appointment_id: appointment.id, body: "manager note" },
         headers: auth(manager), as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
