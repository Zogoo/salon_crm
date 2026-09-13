require "rails_helper"

# Doc 05: add-ons and enhancements may be added before the appointment starts.
RSpec.describe Scheduling::AddAppointmentItem do
  let(:world) { build_world(rooms: { single: 1 }, therapists: 1) }
  let(:owner) { create(:user, email: "ai-owner@example.com", role: "owner") }
  let(:add_on) do
    service = create(:service, name: "Scalp", kind: "add_on")
    variant = create(:service_variant, service:, duration_minutes: 30)
    LocationPrice.create!(location: world[:location], service_variant: variant,
                          price_cents: 3500, effective_from: Date.new(2026, 1, 1))
    StaffQualification.create!(staff_profile: world[:staff].first, service:)
    variant
  end

  it "extends the appointment and its price" do
    appt = book(world)
    was_end = appt.ends_at
    was_total = appt.total_price_cents

    described_class.call(appointment: appt, variant_ids: [ add_on.id ], actor: owner)

    expect(appt.reload.ends_at).to eq(was_end + 30.minutes)
    expect(appt.total_price_cents).to eq(was_total + 3500)
    # The denormalised copy drives the conflict query, so it has to move too.
    expect(appt.appointment_staff.first.ends_at).to eq(appt.ends_at)
  end

  # The extension is a new claim on the room and the therapist, so it has to
  # pass the same conflict check a fresh booking would.
  it "refuses when the extra time collides with the next booking" do
    appt = book(world)
    book(world, start_at: appt.ends_at)
    was_end = appt.ends_at

    expect { described_class.call(appointment: appt, variant_ids: [ add_on.id ], actor: owner) }
      .to raise_error(described_class::Conflict)
    expect(appt.reload.ends_at).to eq(was_end)
    expect(appt.appointment_items.count).to eq(1)
  end

  it "will not add items to a completed appointment" do
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }

    expect { described_class.call(appointment: appt.reload, variant_ids: [ add_on.id ], actor: owner) }
      .to raise_error(described_class::Invalid, /cannot_edit_completed/)
  end
end

RSpec.describe "Add-on scheduling guards" do
  let(:world) { build_world(therapists: 1) }
  let(:appt) { book(world) }
  let(:add_on) do
    service = create(:service, kind: "add_on")
    create(:service_variant, service:, duration_minutes: 30)
  end

  def add
    Scheduling::AddAppointmentItem.call(appointment: appt, variant_ids: [ add_on.id ])
  end

  def qualify
    StaffQualification.create!(staff_profile: world[:staff].first, service: add_on.service)
  end

  it "refuses an add-on the assigned therapist is not qualified to deliver" do
    expect { add }.to raise_error(Scheduling::AddAppointmentItem::Invalid, "therapist_not_qualified")
    expect(appt.reload.appointment_items.count).to eq(1)
  end

  it "refuses an extension past the shift end, including buffer" do
    qualify
    Shift.where(staff_profile: world[:staff].first).update_all(ends_at: appt.ends_at + 15.minutes)
    expect { add }.to raise_error(Scheduling::AddAppointmentItem::Conflict, "therapist_not_on_shift")
    expect(appt.reload.duration_minutes).to eq(60)
  end

  it "refuses an extension into a therapist break" do
    qualify
    shift = Shift.find_by!(staff_profile: world[:staff].first)
    ShiftBreak.create!(shift:, starts_at: appt.ends_at, ends_at: appt.ends_at + 30.minutes)
    expect { add }.to raise_error(Scheduling::AddAppointmentItem::Conflict, "therapist_on_break")
    expect(appt.reload.duration_minutes).to eq(60)
  end

  it "refuses an extension beyond business hours" do
    qualify
    appt
    world[:location].update!(closes_at: "11:30")
    expect { add }.to raise_error(Scheduling::AddAppointmentItem::Conflict, "outside_business_hours")
    expect(appt.reload.duration_minutes).to eq(60)
  end
end
