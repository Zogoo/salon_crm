require "rails_helper"

RSpec.describe Scheduling::RepeatAppointment do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 1) }
  let(:owner) { create(:user, role: "owner") }

  def add_future_shift(weeks)
    original = Shift.first
    date = original.work_date + weeks.weeks
    create(:shift, staff_profile: original.staff_profile, location: original.location,
                   work_date: date, starts_at: original.starts_at.advance(weeks:),
                   ends_at: original.ends_at.advance(weeks:))
  end

  it "creates the requested weekly repeats at the same wall-clock time" do
    appointment = book(world, staff_profile_ids: [ world[:staff].first.id ])
    add_future_shift(1)
    add_future_shift(2)

    repeats = described_class.call(
      appointment:, interval_weeks: 1, count: 2, actor: owner
    )

    expect(repeats.map(&:starts_at)).to eq([ appointment.starts_at + 1.week, appointment.starts_at + 2.weeks ])
    expect(repeats).to all(have_attributes(staff_assignment_confirmed: true))
  end

  it "rolls every repeat back when one future date is unavailable" do
    appointment = book(world, staff_profile_ids: [ world[:staff].first.id ])
    add_future_shift(1)
    before = Appointment.count

    expect {
      described_class.call(appointment:, interval_weeks: 1, count: 2, actor: owner)
    }.to raise_error(Scheduling::RepeatAppointment::Unavailable) { |e|
      expect(e.dates).to contain_exactly(hash_including(code: "therapist_not_on_shift"))
    }

    expect(Appointment.count).to eq(before)
  end
end
