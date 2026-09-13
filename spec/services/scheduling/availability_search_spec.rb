require "rails_helper"

# Doc 03 §2 and §6.1.
RSpec.describe Scheduling::AvailabilitySearch do
  def search(world, **opts)
    described_class.call(
      location: world[:location],
      variants: opts.delete(:variants) || [ world[:variant] ],
      date_from: world[:date], **opts
    ).first[:slots]
  end

  it "offers slots on the location's 15-minute grid" do
    w = build_world
    slots = search(w)
    starts = slots.first(3).map { |s| s.start_at.in_time_zone(w[:location].tz).strftime("%H:%M") }
    expect(starts).to eq(%w[09:00 09:15 09:30])
  end

  it "stops early enough that the service and its buffer both fit before closing" do
    w = build_world
    last = search(w).last
    # 60-minute service + 15-minute buffer, closing at 22:00 -> last start 20:45.
    expect(last.start_at.in_time_zone(w[:location].tz).strftime("%H:%M")).to eq("20:45")
  end

  it "offers nothing outside the therapist's shift" do
    w = build_world(therapists: 1)
    tz = w[:location].tz
    d = w[:date]
    Shift.update_all(starts_at: tz.local(d.year, d.month, d.day, 12, 0),
                     ends_at: tz.local(d.year, d.month, d.day, 15, 0))
    slots = search(w)
    expect(slots.first.start_at.in_time_zone(tz).strftime("%H:%M")).to eq("12:00")
    expect(slots.last.start_at.in_time_zone(tz).strftime("%H:%M")).to eq("13:45")
  end

  it "removes a booked interval, including its buffer" do
    w = build_world(rooms: { single: 1 }, therapists: 1)
    appt = Scheduling::BookAppointment.call(
      location: w[:location], client: w[:client],
      variant_ids: [ w[:variant].id ], start_at: w[:at]
    )
    times = search(w).map(&:start_at)
    expect(times).not_to include(appt.starts_at)
    expect(times).not_to include(appt.service_ends_at)   # inside the buffer
    expect(times).to include(appt.ends_at)               # buffer over
  end

  it "excludes a therapist who is not qualified" do
    w = build_world(therapists: 1)
    StaffQualification.delete_all
    expect(search(w)).to be_empty
  end

  it "excludes time covered by a shift break" do
    w = build_world(therapists: 1)
    shift = Shift.first
    ShiftBreak.create!(shift:, starts_at: w[:at], ends_at: w[:at] + 1.hour)
    times = search(w).map { |s| s.start_at }
    expect(times).not_to include(w[:at])
  end

  it "offers a two-therapist service only when two are free" do
    couples_service = create(:service, name: "Couples")
    couples = create(:service_variant, service: couples_service, duration_minutes: 60,
                                       therapist_count: 2, required_client_capacity: 2)
    w = build_world(rooms: { couple: 1 }, therapists: 2)
    w[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service: couples_service) }
    expect(search(w, variants: [ couples ])).not_to be_empty

    # Take one therapist out and the service stops being offered at all.
    Shift.where(staff_profile_id: w[:staff].last.id).delete_all
    expect(search(w, variants: [ couples ])).to be_empty
  end

  it "sums an add-on into the searched duration" do
    w = build_world
    add_on_service = create(:service, name: "Scalp", kind: "add_on")
    add_on = create(:service_variant, service: add_on_service, duration_minutes: 30)
    w[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service: add_on_service) }

    slots = search(w, variants: [ w[:variant], add_on ])
    slot = slots.first
    expect(((slot.service_end_at - slot.start_at) / 60).round).to eq(90)
    # 90 + 15 buffer, closing 22:00 -> last start 20:15.
    expect(slots.last.start_at.in_time_zone(w[:location].tz).strftime("%H:%M")).to eq("20:15")
  end

  it "applies the booking cut-off and horizon on the client channel only" do
    w = build_world(date: Date.current)
    tz = w[:location].tz
    noon = tz.local(w[:date].year, w[:date].month, w[:date].day, 12, 0)

    manager = described_class.call(location: w[:location], variants: [ w[:variant] ],
                                   date_from: w[:date], channel: "manager", now: noon).first[:slots]
    client = described_class.call(location: w[:location], variants: [ w[:variant] ],
                                  date_from: w[:date], channel: "client", now: noon).first[:slots]

    expect(manager.map(&:start_at).min).to be < noon        # front desk may book the past-adjacent
    expect(client.map(&:start_at).min).to be >= noon + w[:location].booking_cutoff_minutes.minutes
  end
end

RSpec.describe "Requested therapist for two-therapist services" do
  [ 1, 2 ].each do |capacity|
    context "with client capacity #{capacity}" do
      let(:world) { build_world(rooms: { couple: 2 }, therapists: 3) }
      let(:variant) { create(:service_variant, service: world[:service], duration_minutes: 90, therapist_count: 2, required_client_capacity: capacity) }
      let(:requested) { world[:staff].last }

      def slots
        Scheduling::AvailabilitySearch.call(location: world[:location], variants: [ variant ],
          date_from: world[:date], requested_staff_profile_id: requested.id.to_s).first[:slots]
      end

      it "offers a pair including the requested therapist and books it with approval" do
        slot = slots.first
        expect(slot).to be_present
        expect(slot.staff.pluck(:id)).to include(requested.id)
        appt = book(world, variant_ids: [ variant.id ], start_at: slot.start_at, requested_staff_profile_id: requested.id)
        expect(appt.staff_profiles.count).to eq(2)
        expect(appt.staff_profiles).to include(requested)
        expect(appt.status).to eq("pending_approval")
        expect(appt.approval_request.requested_staff_profile_id).to eq(requested.id)
      end

      it "does not substitute other free therapists when the requested one is busy" do
        book(world, staff_profile_ids: [ requested.id ])
        expect(slots.map(&:start_at)).not_to include(world[:at])
        expect { book(world, variant_ids: [ variant.id ], requested_staff_profile_id: requested.id) }
          .to raise_error(Scheduling::BookAppointment::Conflict)
      end

      it "offers nothing when the requested therapist has no covering shift" do
        Shift.where(staff_profile: requested).delete_all
        expect(slots).to be_empty
        expect { book(world, variant_ids: [ variant.id ], requested_staff_profile_id: requested.id) }
          .to raise_error(Scheduling::BookAppointment::Conflict)
      end

      it "rejects an explicit pair that excludes the requested therapist" do
        expect { book(world, variant_ids: [ variant.id ], requested_staff_profile_id: requested.id,
                      staff_profile_ids: world[:staff].first(2).map(&:id)) }
          .to raise_error(Scheduling::BookAppointment::Invalid, "requested_therapist_missing")
      end
    end
  end
end
