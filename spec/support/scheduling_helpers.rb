# Builds the smallest world in which a booking is possible: a location with
# rooms, a menu, therapists qualified for it, and shifts covering the day.
module SchedulingHelpers
  def build_world(rooms: { single: 2 }, therapists: 2, date: Date.current.next_occurring(:monday))
    location = create(:location, code: "test#{SecureRandom.hex(3)}")
    capacity = { single: 1, couple: 2, three_table: 3, head_spa: 2 }

    rooms.each do |type, count|
      count.times do |i|
        create(:room, location:, name: "#{type}-#{i}", room_type: type.to_s,
                      client_capacity: capacity.fetch(type), exclusive: type == :head_spa,
                      position: i)
      end
    end

    service = create(:service, name: "Massage #{SecureRandom.hex(2)}")
    variant = create(:service_variant, service:, duration_minutes: 60)

    staff = Array.new(therapists) do |i|
      user = create(:user, email: "t#{i}-#{SecureRandom.hex(3)}@example.com", role: "staff")
      profile = create(:staff_profile, user:, location:, display_name: "T#{i}")
      StaffQualification.create!(staff_profile: profile, service:)
      ServiceVariant::LADDER.each do |d|
        StaffSessionRate.create!(staff_profile: profile, duration_minutes: d,
                                 rate_cents: d * 75, effective_from: Date.new(2026, 1, 1))
      end
      tz = location.tz
      create(:shift, staff_profile: profile, location:, work_date: date,
                     starts_at: tz.local(date.year, date.month, date.day, 9, 0),
                     ends_at: tz.local(date.year, date.month, date.day, 22, 0))
      profile
    end

    client = create(:client)
    at = location.tz.local(date.year, date.month, date.day, 10, 0)
    { location:, service:, variant:, staff:, client:, date:, at: }
  end

  # A booking with no named therapist holds a *provisional* one until the desk
  # confirms it (feedback 2.2), and a provisional booking cannot be completed.
  # Most specs are about what happens after assignment, so the helper confirms
  # by default; pass `provisional: true` to test the unassigned state itself.
  def book(world, provisional: false, **overrides)
    appt = Scheduling::BookAppointment.call(
      location: world[:location], client: world[:client],
      variant_ids: overrides.delete(:variant_ids) || [ world[:variant].id ],
      start_at: overrides.delete(:start_at) || world[:at],
      **overrides
    )
    appt.update!(staff_assignment_confirmed: true) unless provisional || appt.staff_assignment_confirmed?
    appt
  end
end

RSpec.configure { |c| c.include SchedulingHelpers }
