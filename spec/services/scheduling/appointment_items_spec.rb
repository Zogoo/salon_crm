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
