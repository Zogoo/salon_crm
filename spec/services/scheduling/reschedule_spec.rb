require "rails_helper"

# Doc 03 §4.6.
RSpec.describe Scheduling::RescheduleAppointment do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "rs-owner@example.com", role: "owner") }

  it "creates a new appointment and releases the old one, keeping the chain" do
    original = book(world)
    moved = described_class.call(appointment: original, start_at: world[:at] + 3.hours, actor: owner)

    expect(original.reload.status).to eq("cancelled")
    expect(original.cancellation_reason).to eq("rescheduled")
    expect(moved.status).to eq("scheduled")
    expect(moved.rescheduled_from_id).to eq(original.id)
    expect(moved.starts_at).to eq(world[:at] + 3.hours)
  end

  it "carries the services, note and therapist across" do
    original = book(world, staff_profile_ids: [ world[:staff].first.id ],
                           client_note: "Prefers firm pressure")
    moved = described_class.call(appointment: original, start_at: world[:at] + 4.hours, actor: owner)

    expect(moved.client_note).to eq("Prefers firm pressure")
    expect(moved.staff_profiles.map(&:id)).to eq([ world[:staff].first.id ])
    expect(moved.appointment_items.map(&:service_variant_id))
      .to eq(original.appointment_items.map(&:service_variant_id))
  end

  # The reason it releases before booking: an overlapping move would otherwise
  # collide with itself.
  it "can move an appointment onto a time that overlaps its own old slot" do
    w = build_world(rooms: { single: 1 }, therapists: 1)
    original = book(w)

    expect {
      described_class.call(appointment: original, start_at: w[:at] + 30.minutes, actor: owner)
    }.not_to raise_error
  end

  it "leaves the original alone when the new time is taken" do
    original = book(world)
    blocker_at = world[:at] + 5.hours
    world[:staff].each { |sp| book(world, start_at: blocker_at, staff_profile_ids: [ sp.id ]) }

    expect { described_class.call(appointment: original, start_at: blocker_at, actor: owner) }
      .to raise_error(Scheduling::BookAppointment::Conflict)
    # The transaction rolled back, so the client still has their original time.
    expect(original.reload.status).to eq("scheduled")
  end

  it "refuses to reschedule something already completed" do
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }

    expect { described_class.call(appointment: appt.reload, start_at: world[:at] + 6.hours, actor: owner) }
      .to raise_error(Scheduling::BookAppointment::Invalid, "cannot_reschedule_completed")
  end
end

RSpec.describe "Shift breaks", type: :request do
  let(:world) { build_world(rooms: { single: 1 }, therapists: 1) }
  let(:owner) { create(:user, email: "sb-owner@example.com", role: "owner") }
  let(:shift) { Shift.first }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }

  it "records a break, which then removes those times from availability" do
    tz = world[:location].tz
    post "/api/v1/shifts/#{shift.id}/breaks",
         params: { starts_at: "12:00", ends_at: "13:00", reason: "lunch" },
         headers: auth(owner), as: :json
    expect(response).to have_http_status(:created)

    slots = Scheduling::AvailabilitySearch.call(
      location: world[:location], variants: [ world[:variant] ], date_from: world[:date]
    ).first[:slots]

    noon = tz.local(world[:date].year, world[:date].month, world[:date].day, 12, 0)
    expect(slots.map(&:start_at)).not_to include(noon)
  end

  it "refuses a break dropped on top of a booking" do
    appt = book(world)   # 10:00
    post "/api/v1/shifts/#{shift.id}/breaks",
         params: { starts_at: "10:00", ends_at: "11:00" },
         headers: auth(owner), as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).dig("error", "details", "appointment_ids")).to include(appt.id)
  end
end
