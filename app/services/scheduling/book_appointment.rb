module Scheduling
  # The single writer of appointments. Doc 08 §2, ADR-17.
  #
  # Under PostgreSQL, double-booking was impossible because two EXCLUDE
  # constraints rejected an overlapping row no matter which code path inserted
  # it. SQLite has no such constraint, so the guarantee now rests on two things
  # together:
  #
  #   1. every conflict check runs inside BEGIN IMMEDIATE, so the write lock is
  #      already held when the check runs — Rails' default deferred transaction
  #      takes it lazily, leaving exactly the race the constraint used to close;
  #   2. nothing else in the codebase inserts an appointment.
  #
  # If a second writer is ever added, the guarantee is gone. The concurrency
  # spec (doc 03 §6.1 test 1) is what stands in for the constraint.
  class BookAppointment < ApplicationService
    Conflict = Class.new(StandardError)
    Invalid  = Class.new(StandardError)

    def initialize(location:, client:, variant_ids:, start_at:, actor: nil,
                   staff_profile_ids: nil, room_id: nil, requested_staff_profile_id: nil,
                   booking_channel: "manager", client_note: nil, appointment_note: nil,
                   participant_client_ids: [])
      @location = location
      @client = client
      @variants = ServiceVariant.active.where(id: variant_ids).includes(:service).to_a
      @start_at = start_at
      @actor = actor
      @staff_ids = Array(staff_profile_ids).compact.map(&:to_i).uniq
      @room_id = room_id
      @requested_staff_id = requested_staff_profile_id.presence&.to_i
      @channel = booking_channel
      @client_note = client_note
      @appointment_note = appointment_note
      @participant_ids = Array(participant_client_ids).compact.map(&:to_i)
    end

    def call
      raise Invalid, "unknown service" if @variants.empty?
      shape = AppointmentShape.call(variants: @variants)
      finish = @start_at + (shape.duration_minutes + @location.buffer_minutes).minutes
      service_end = @start_at + shape.duration_minutes.minutes

      assert_location_open!(finish)

      ImmediateTransaction.call do
        staff = resolve_staff(shape, finish)
        room  = resolve_room(shape, finish)

        assert_room_free!(room, finish)
        assert_staff_free!(staff, finish)

        appt = create_appointment!(shape, room, service_end, finish)
        attach_staff!(appt, staff)
        attach_items!(appt)
        attach_participants!(appt)
        record_event!(appt)
        create_approval_request!(appt)
        confirm!(appt)
        appt
      end
    end

    private

    def pending_approval? = @requested_staff_id.present?
    def status = pending_approval? ? "pending_approval" : "scheduled"

    # --- resolution -------------------------------------------------------

    def resolve_staff(shape, finish)
      ids = @staff_ids
      if ids.any? && @requested_staff_id && !ids.include?(@requested_staff_id)
        raise Invalid, "requested_therapist_missing"
      end

      staff =
        if ids.any?
          StaffProfile.active.where(id: ids).to_a
        else
          assign_staff(shape, finish)
        end

      raise Invalid, "therapist not found" if staff.size < ids.size
      unless staff.size == shape.therapist_count
        raise Conflict, "insufficient_therapists"    # C12 — cardinality
      end
      staff.each { |sp| assert_eligible!(sp, shape, finish) }
      staff
    end

    # BR-09a: smallest sufficient room, so a couple room is not consumed by a
    # solo booking while a single room stands empty.
    def resolve_room(shape, finish)
      if @room_id.present?
        room = Room.active.find_by(id: @room_id, location_id: @location.id)
        raise Invalid, "room not found" unless room
        raise Conflict, "no_suitable_room" unless room_matches?(room, shape)
        return room
      end

      candidates = Room.suitable_for(shape.room_requirement)
                       .where(location_id: @location.id)
                       .order(:client_capacity, :position, :id)
                       .to_a
      # Distinguish "we have no such room" from "the room is busy". The first is
      # permanent and the UI should say so; the second is a race the caller can
      # retry at another time.
      raise Conflict, "no_suitable_room" if candidates.empty?

      room = candidates.find { |r| !room_clash?(r, finish) }
      raise Conflict, "slot_taken" unless room
      room
    end

    def room_matches?(room, shape)
      return false if room.client_capacity < shape.required_client_capacity
      if shape.requires_room_type.present?
        room.room_type == shape.requires_room_type
      else
        !room.exclusive
      end
    end

    def assign_staff(shape, finish)
      day = @start_at.in_time_zone(@location.tz).to_date
      candidates = Shift.published
           .where(location_id: @location.id, work_date: day)
           .includes(:shift_breaks, staff_profile: :staff_qualifications)
           .select { |s| eligible?(s, shape, finish) }
           .map(&:staff_profile).uniq
      if @requested_staff_id
        requested = candidates.find { |sp| sp.id == @requested_staff_id }
        raise Conflict, "requested_therapist_unavailable" unless requested
        candidates = [ requested ] + (candidates - [ requested ])
      end
      candidates.first(shape.therapist_count)
    end

    def eligible?(shift, shape, finish)
      sp = shift.staff_profile
      sp.status == "active" &&
        sp.qualified_for?(shape.service_ids) &&
        shift.covers?(@start_at, finish) &&
        shift.shift_breaks.none? { |b| b.starts_at < finish && b.ends_at > @start_at } &&
        !staff_clash?(sp.id, finish)
    end

    # --- the checks that replace the exclusion constraints -----------------

    def assert_eligible!(sp, shape, finish)
      raise Invalid, "therapist not qualified" unless sp.qualified_for?(shape.service_ids)

      shift = Shift.published
                   .where(staff_profile_id: sp.id, location_id: @location.id)
                   .overlapping(@start_at, finish).includes(:shift_breaks).first
      raise Conflict, "therapist_not_on_shift" unless shift&.covers?(@start_at, finish)   # C4

      if shift.shift_breaks.any? { |b| b.starts_at < finish && b.ends_at > @start_at }    # C6
        raise Conflict, "therapist_on_break"
      end
    end

    # Invariant 1 — room overlap. `ends_at` carries the 15-minute buffer, so
    # BR-10's gap rule falls out of this same check (doc 03 §1.1).
    def assert_room_free!(room, finish)
      raise Conflict, "slot_taken" if room_clash?(room, finish)
    end

    # Invariant 2 — therapist overlap, company-wide (C5).
    def assert_staff_free!(staff, finish)
      staff.each { |sp| raise Conflict, "slot_taken" if staff_clash?(sp.id, finish) }
    end

    # A blocked room is as unavailable as a booked one (doc 02 §3.2), so the
    # single writer treats them the same.
    def room_clash?(room, finish)
      Appointment.active.overlapping(@start_at, finish).exists?(room_id: room.id) ||
        RoomBlock.overlapping(@start_at, finish).exists?(room_id: room.id)
    end

    # C1 — the availability search hides closed days, but nothing stops a
    # direct POST, and BookAppointment is the only writer that can refuse it.
    def assert_location_open!(finish)
      date = @start_at.in_time_zone(@location.tz).to_date
      windows = @location.business_windows(date)
      raise Conflict, "location_closed" if windows.empty?

      covered = windows.any? { |w| @start_at >= w.first && finish <= w.last }
      raise Conflict, "outside_business_hours" unless covered
    end

    def staff_clash?(staff_id, finish)
      AppointmentStaff.active.overlapping(@start_at, finish)
                      .exists?(staff_profile_id: staff_id)
    end

    # --- writes -----------------------------------------------------------

    def create_appointment!(shape, room, service_end, finish)
      Appointment.create!(
        reference: Appointment.generate_reference,
        client: @client, location: @location, room: room,
        starts_at: @start_at, service_ends_at: service_end, ends_at: finish,
        status: status,
        total_price_cents: @variants.sum { |v| price_for(v) },
        booking_channel: @channel,
        created_by_user: @actor,
        requested_staff_profile_id: @requested_staff_id,
        client_note: @client_note, appointment_note: @appointment_note
      )
    end

    def attach_staff!(appt, staff)
      staff.each_with_index do |sp, i|
        AppointmentStaff.create!(
          appointment: appt, staff_profile: sp,
          role: i.zero? ? "primary" : "secondary",
          starts_at: appt.starts_at, ends_at: appt.ends_at, status: appt.status
        )
      end
    end

    def attach_items!(appt)
      @variants.each_with_index do |v, i|
        AppointmentItem.create!(
          appointment: appt, service_variant: v, kind: v.item_kind,
          duration_minutes: v.payable? ? v.duration_minutes : 0,
          price_cents: price_for(v), position: i
        )
      end
    end

    def attach_participants!(appt)
      ids = ([ @client.id ] + @participant_ids).uniq
      ids.each_with_index do |cid, i|
        AppointmentParticipant.create!(appointment: appt, client_id: cid, position: i + 1)
      end
    end

    def record_event!(appt)
      AppointmentStatusEvent.create!(
        appointment: appt, from_status: nil, to_status: appt.status,
        actor_user: @actor, occurred_at: Time.current, reason: "booked"
      )
    end

    # A booking that is already confirmed notifies now; one that is waiting on a
    # therapist approval notifies when it is approved, via TransitionStatus.
    def confirm!(appt)
      return if pending_approval?
      Notifications::Confirm.call(appointment: appt)
    end

    # BR-15: the request holds the slot from creation, so nobody can take it
    # while approval is outstanding.
    def create_approval_request!(appt)
      return unless pending_approval?
      ApprovalRequest.create!(
        appointment: appt, requested_staff_profile_id: @requested_staff_id,
        requested_by_user: @actor, status: "pending"
      )
    end

    def price_for(variant)
      @prices ||= {}
      @prices[variant.id] ||= Catalogue::ResolvePrice.call(
        variant:, location: @location, on: @start_at.to_date
      )
    end
  end
end
