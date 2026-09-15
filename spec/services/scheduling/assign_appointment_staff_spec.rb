require "rails_helper"

RSpec.describe Scheduling::AssignAppointmentStaff do
  let(:world) { build_world(rooms: { single: 1 }, therapists: 2) }
  let(:owner) { create(:user, role: "owner") }

  it "keeps capacity reserved while a no-preference booking awaits assignment" do
    appointment = book(world, provisional: true)

    expect(appointment.staff_assignment_confirmed).to be(false)
    expect(appointment.staff_profiles).not_to be_empty
  end

  it "confirms an eligible therapist chosen by the desk" do
    appointment = book(world, provisional: true)
    chosen = world[:staff].last

    described_class.call(appointment:, staff_profile_ids: [ chosen.id ], actor: owner)

    expect(appointment.reload.staff_assignment_confirmed).to be(true)
    expect(appointment.staff_profiles.ids).to eq([ chosen.id ])
    expect(AuditLog.where(auditable_type: "Appointment", auditable_id: appointment.id,
                          action: "appointment.staff_assigned")).to exist
  end

  it "does not discard the reservation when the requested team size is wrong" do
    appointment = book(world, provisional: true)
    original_ids = appointment.staff_profiles.ids

    expect {
      described_class.call(appointment:, staff_profile_ids: [], actor: owner)
    }.to raise_error(described_class::Invalid, "wrong_therapist_count")

    expect(appointment.reload.staff_profiles.ids).to eq(original_ids)
  end
end
