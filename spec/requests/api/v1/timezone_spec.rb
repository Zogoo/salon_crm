require "rails_helper"

# Doc 03 §5: every instant crossing the API is rendered in the *location's*
# wall clock. Rails serialises in Time.zone (UTC) by default, and the client
# renders the wall clock straight out of the string — so a bare "Z" shows a
# Chicago manager the wrong hour, and after 19:00 the wrong day.
#
# These assert the shape rather than a value, so they hold whatever the clock
# says when the suite runs.
RSpec.describe "API timestamps carry the salon's offset", type: :request do
  ZONED = /[+-]\d{2}:\d{2}\z/   # an offset, not a bare Z

  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "tz-owner@example.com", role: "owner") }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  def complete(appt)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    appt.reload
  end

  it "zones appointment times" do
    appt = book(world)
    get "/api/v1/appointments/#{appt.id}", headers: auth(owner)

    expect(json["starts_at"]).to match(ZONED)
    expect(json["service_ends_at"]).to match(ZONED)
    expect(json["ends_at"]).to match(ZONED)
  end

  it "zones availability slots" do
    get "/api/v1/availability",
        params: { location_id: world[:location].id,
                  service_variant_ids: [ world[:variant].id ],
                  date_from: world[:date].to_s },
        headers: auth(owner)

    slot = json["days"].first["slots"].first
    expect(slot["start_at"]).to match(ZONED)
    expect(slot["end_at"]).to match(ZONED)
  end

  it "zones gift card dates" do
    GiftCards::IssueCard.call(location: world[:location], amount_cents: 5_000,
                              payment_method: "cash", actor: owner, buyer_name: "B")
    get "/api/v1/gift_cards", headers: auth(owner)

    card = json["gift_cards"].first
    expect(card["sold_at"]).to match(ZONED)
    expect(card["expires_at"]).to match(ZONED)
  end

  # The renewal date drives the 15-day cancellation rule, so the wrong day here
  # is a customer-facing error rather than a cosmetic one.
  it "zones the membership renewal date" do
    membership = Memberships::Enrol.call(client: world[:client], location: world[:location],
                                         actor: owner, default_service_variant_id: world[:variant].id)
    get "/api/v1/memberships/#{membership.id}", headers: auth(owner)

    expect(json["current_period_end"]).to match(ZONED)
  end

  it "zones the approval queue's auto-approve time" do
    book(world, requested_staff_profile_id: world[:staff].first.id)
    get "/api/v1/approval_requests", headers: auth(owner)

    request = json["approval_requests"].first
    expect(request["auto_approves_at"]).to match(ZONED)
    expect(request["appointment"]["starts_at"]).to match(ZONED)
  end

  it "zones shift times" do
    get "/api/v1/shifts",
        params: { location_id: world[:location].id, date: world[:date].to_s },
        headers: auth(owner)

    shift = json["working"].first
    expect(shift["starts_at"]).to match(ZONED)
    expect(shift["ends_at"]).to match(ZONED)
  end

  it "zones the outstanding-fee digest" do
    appt = book(world)
    Scheduling::TransitionStatus.call(appointment: appt, to: "no_show")
    get "/api/v1/reports/outstanding_fees",
        params: { location_id: world[:location].id }, headers: auth(owner)

    expect(json["orders"].first["created_at"]).to match(ZONED)
  end

  it "zones staff request timestamps" do
    profile = world[:staff].first
    StaffRequest.create!(staff_profile: profile, kind: "shift_change",
                         status: "submitted", requested_payload: { "note" => "swap" })
    get "/api/v1/staff_requests", headers: auth(owner)

    expect(json["staff_requests"].first["created_at"]).to match(ZONED)
  end

  it "zones the gift card liability as-of instant" do
    get "/api/v1/reports/gift_card_liability",
        params: { location_id: world[:location].id }, headers: auth(owner)

    expect(json["as_of"]).to match(ZONED)
  end

  it "zones care note timestamps" do
    appt = book(world)
    Crm::RecordCareNote.call(appointment: appt, staff_profile: appt.staff_profiles.first, body: "n")
    get "/api/v1/care_notes", params: { appointment_id: appt.id }, headers: auth(owner)

    expect(json["care_notes"].first["created_at"]).to match(ZONED)
  end
end
