require "rails_helper"

# Doc 05 §"Clients" and BR-42/BR-43/BR-44/BR-46.
RSpec.describe "Client record API", type: :request do
  let(:world)   { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner)   { create(:user, email: "cr-owner@example.com", role: "owner") }
  let(:client)  { world[:client] }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  def complete(appt)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    appt.reload
  end

  it "summarises who this client is at a glance (BR-46)" do
    appt = complete(book(world))

    get "/api/v1/clients/#{client.id}/history_summary", headers: auth(owner)

    expect(response).to have_http_status(:ok)
    expect(json["visits"]).to eq(1)
    expect(json["lifetime_spend_cents"]).to eq(appt.total_price_cents)
    expect(json["favourite_therapist"]).to eq(appt.staff_profiles.first.display_name)
    expect(json["days_since_last_visit"]).to be_a(Integer)
  end

  it "lists the client's appointments across every location (BR-42)" do
    book(world)
    get "/api/v1/clients/#{client.id}/appointments", headers: auth(owner)
    expect(json["appointments"].size).to eq(1)
  end

  # BR-43: the form is versioned, never destructively overwritten.
  it "keeps the previous preference form readable after an edit" do
    put "/api/v1/clients/#{client.id}/preferences",
        params: { preference: { attention_areas: "Shoulders", pressure: "medium" } },
        headers: auth(owner), as: :json
    put "/api/v1/clients/#{client.id}/preferences",
        params: { preference: { attention_areas: "Lower back", pressure: "firm" } },
        headers: auth(owner), as: :json

    get "/api/v1/clients/#{client.id}/preferences", headers: auth(owner)
    expect(json.dig("preference", "attention_areas")).to eq("Lower back")

    get "/api/v1/clients/#{client.id}/preferences/versions", headers: auth(owner)
    expect(json["versions"].first["attention_areas"]).to eq("Shoulders")
  end

  # BR-44: a correction is a new note, and the original stays readable.
  it "supersedes a care note instead of editing it" do
    appt = book(world)
    therapist = appt.staff_profiles.first
    original = Crm::RecordCareNote.call(appointment: appt, staff_profile: therapist, body: "Avoid left knee")

    post "/api/v1/care_notes/#{original.id}/supersede",
         params: { body: "Avoid right knee" }, headers: auth(therapist.user), as: :json

    expect(response).to have_http_status(:created)
    expect(CareNote.find(original.id).body).to eq("Avoid left knee")
    expect(CareNote.find(json["id"]).supersedes_note_id).to eq(original.id)
  end

  it "refuses to let one therapist correct another's note" do
    appt = book(world)
    author = appt.staff_profiles.first
    other = (world[:staff] - [ author ]).first
    note = Crm::RecordCareNote.call(appointment: appt, staff_profile: author, body: "Note")

    post "/api/v1/care_notes/#{note.id}/supersede",
         params: { body: "Not mine to correct" }, headers: auth(other.user), as: :json

    expect(response).to have_http_status(:not_found)
  end
end
