require "rails_helper"

# Doc 03 §6.1. With no Postgres exclusion constraint these specs *are* the
# double-booking guarantee, not a check on it (doc 08 §2). Do not delete or
# skip any of them.
RSpec.describe Scheduling::BookAppointment do
  describe "room and therapist conflicts" do
    it "books into the smallest sufficient room (BR-09a)" do
      w = build_world(rooms: { single: 1, couple: 1 })
      appt = book(w)
      expect(appt.room.room_type).to eq("single")
    end

    it "refuses a second appointment in the same room at the same time" do
      w = build_world(rooms: { single: 1 }, therapists: 2)
      book(w)
      expect { book(w) }.to raise_error(described_class::Conflict, "slot_taken")
    end

    it "refuses the same therapist at the same time in a different room" do
      w = build_world(rooms: { single: 2 })
      first = book(w)
      therapist = first.staff_profiles.first
      expect { book(w, staff_profile_ids: [ therapist.id ]) }
        .to raise_error(described_class::Conflict, "slot_taken")
    end

    # C5: therapist conflicts are company-wide, room conflicts are not.
    #
    # BR-04 already forbids overlapping shifts across locations, so in clean
    # data this case cannot arise. The check exists as defence in depth: the
    # booking guarantee must not depend on shift data being correct. The second
    # shift is therefore written past its own validation on purpose, to prove
    # the conflict check stands on its own.
    it "refuses a therapist already booked at another location" do
      w = build_world
      other = create(:location, code: "other#{SecureRandom.hex(2)}")
      create(:room, location: other, room_type: "single", client_capacity: 1)
      therapist = w[:staff].first
      book(w, staff_profile_ids: [ therapist.id ])

      bad_shift = Shift.new(staff_profile: therapist, location: other, work_date: w[:date],
                            starts_at: w[:at] - 2.hours, ends_at: w[:at] + 6.hours,
                            status: "published")
      bad_shift.save!(validate: false)

      expect {
        Scheduling::BookAppointment.call(
          location: other, client: w[:client], variant_ids: [ w[:variant].id ],
          start_at: w[:at], staff_profile_ids: [ therapist.id ]
        )
      }.to raise_error(described_class::Conflict, "slot_taken")
    end

    it "refuses overlapping shifts for one therapist, company-wide (BR-04)" do
      w = build_world
      other = create(:location, code: "other#{SecureRandom.hex(2)}")
      shift = Shift.new(staff_profile: w[:staff].first, location: other, work_date: w[:date],
                        starts_at: w[:at], ends_at: w[:at] + 2.hours, status: "published")
      expect(shift).not_to be_valid
      expect(shift.errors.full_messages.join).to match(/overlaps another published shift/)
    end
  end

  describe "the 15-minute buffer (BR-10)" do
    it "refuses a booking that starts inside the previous one's buffer" do
      w = build_world(rooms: { single: 1 }, therapists: 3)
      first = book(w)
      expect { book(w, start_at: first.service_ends_at, room_id: first.room_id) }
        .to raise_error(described_class::Conflict, "slot_taken")
    end

    it "allows a booking that starts exactly at the end of the buffer" do
      w = build_world(rooms: { single: 1 }, therapists: 3)
      first = book(w)
      expect { book(w, start_at: first.ends_at, room_id: first.room_id) }.not_to raise_error
    end
  end

  describe "multi-therapist services (C12)" do
    let(:couples) do
      service = create(:service, name: "Couples")
      create(:service_variant, service:, duration_minutes: 90,
                               therapist_count: 2, required_client_capacity: 2)
    end

    def qualify_all(world, service)
      world[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service:) }
    end

    it "books two therapists into one couple room" do
      w = build_world(rooms: { couple: 1 }, therapists: 2)
      qualify_all(w, couples.service)
      appt = book(w, variant_ids: [ couples.id ])
      expect(appt.staff_profiles.count).to eq(2)
      expect(appt.room.room_type).to eq("couple")
    end

    it "refuses when only one therapist is free — cardinality, not existence" do
      w = build_world(rooms: { couple: 2 }, therapists: 1)
      qualify_all(w, couples.service)
      expect { book(w, variant_ids: [ couples.id ]) }
        .to raise_error(described_class::Conflict, "insufficient_therapists")
    end

    it "rolls the whole appointment back when the second therapist is taken" do
      w = build_world(rooms: { couple: 1, single: 1 }, therapists: 2)
      qualify_all(w, couples.service)
      taken = w[:staff].last
      book(w, staff_profile_ids: [ taken.id ])          # occupies one therapist

      before = Appointment.count
      expect { book(w, variant_ids: [ couples.id ]) }.to raise_error(described_class::Conflict)
      expect(Appointment.count).to eq(before)            # no half-created booking
      expect(AppointmentStaff.where(appointment_id: nil)).to be_empty
    end

    it "refuses a couples service in a single room" do
      w = build_world(rooms: { single: 3 }, therapists: 2)
      qualify_all(w, couples.service)
      expect { book(w, variant_ids: [ couples.id ]) }
        .to raise_error(described_class::Conflict, "no_suitable_room")
    end
  end

  describe "exclusive rooms (C11)" do
    it "keeps non-head-spa services out of a head-spa room" do
      w = build_world(rooms: { head_spa: 2 })
      expect { book(w) }.to raise_error(described_class::Conflict, "no_suitable_room")
    end

    it "places a head-spa service in a head-spa room" do
      w = build_world(rooms: { head_spa: 1, single: 1 })
      service = create(:service, name: "Head spa")
      variant = create(:service_variant, service:, duration_minutes: 60,
                                         requires_room_type: "head_spa")
      w[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service:) }
      appt = book(w, variant_ids: [ variant.id ])
      expect(appt.room.room_type).to eq("head_spa")
    end
  end

  describe "qualification and shifts" do
    it "refuses a therapist not qualified for the service" do
      w = build_world
      other_service = create(:service, name: "Unqualified")
      variant = create(:service_variant, service: other_service, duration_minutes: 60)
      expect { book(w, variant_ids: [ variant.id ], staff_profile_ids: [ w[:staff].first.id ]) }
        .to raise_error(described_class::Invalid, /not qualified/)
    end

    it "refuses a therapist whose shift does not cover the whole appointment" do
      w = build_world(therapists: 1)
      Shift.update_all(ends_at: w[:at] + 30.minutes)     # ends mid-appointment
      expect { book(w, staff_profile_ids: [ w[:staff].first.id ]) }
        .to raise_error(described_class::Conflict, "therapist_not_on_shift")
    end
  end

  describe "pricing and items" do
    it "snapshots the location price at booking (BR-11)" do
      w = build_world
      LocationPrice.create!(location: w[:location], service_variant: w[:variant],
                            price_cents: 12_345, effective_from: Date.new(2026, 1, 1))
      appt = book(w)
      expect(appt.total_price_cents).to eq(12_345)
    end

    it "sums an add-on into the duration and price, as one appointment" do
      w = build_world
      add_on_service = create(:service, name: "Scalp", kind: "add_on")
      add_on = create(:service_variant, service: add_on_service, duration_minutes: 30,
                                        base_price_cents: 3500)
      w[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service: add_on_service) }

      appt = book(w, variant_ids: [ w[:variant].id, add_on.id ])
      expect(appt.duration_minutes).to eq(90)
      expect(appt.total_price_cents).to eq(11_500)
      expect(appt.appointment_items.count).to eq(2)
      expect(appt.ends_at).to eq(appt.service_ends_at + 15.minutes)
    end

    it "gives an enhancement price but no time (OQ-07)" do
      w = build_world
      enh_service = create(:service, name: "Hot stone", kind: "enhancement")
      enh = create(:service_variant, service: enh_service, duration_minutes: 0,
                                     base_price_cents: 1500)
      appt = book(w, variant_ids: [ w[:variant].id, enh.id ])
      expect(appt.duration_minutes).to eq(60)
      expect(appt.total_price_cents).to eq(9500)
    end
  end

  describe "specific-therapist requests (BR-15)" do
    it "holds the slot as pending_approval and blocks other bookings" do
      w = build_world(rooms: { single: 1 }, therapists: 2)
      appt = book(w, requested_staff_profile_id: w[:staff].first.id)
      expect(appt.status).to eq("pending_approval")
      expect(appt.approval_request).to be_present
      expect { book(w) }.to raise_error(described_class::Conflict, "slot_taken")
    end
  end
end
