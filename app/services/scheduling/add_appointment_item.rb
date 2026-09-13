module Scheduling
  # Doc 05 §"Appointments": add-ons and enhancements can be added before the
  # appointment starts.
  #
  # An enhancement adds price and no time, so it is a price change. An add-on
  # adds 30 minutes, which moves the end of the appointment — and a longer
  # appointment can collide with the next one in the room or with the
  # therapist's next booking. So the extension is re-checked against exactly
  # the same conflict rules as a new booking, inside the same write lock.
  class AddAppointmentItem < ApplicationService
    Invalid  = Class.new(StandardError)
    Conflict = Class.new(StandardError)

    EDITABLE = %w[pending_approval scheduled checked_in].freeze

    def initialize(appointment:, variant_ids:, actor: nil)
      @appt = appointment
      @variants = ServiceVariant.active.where(id: Array(variant_ids)).includes(:service).to_a
      @actor = actor
    end

    def call
      raise Invalid, "no_items" if @variants.empty?
      raise Invalid, "cannot_edit_#{@appt.status}" unless EDITABLE.include?(@appt.status)
      raise Invalid, "service_items_not_addable" if @variants.any? { |v| v.item_kind == "service" }

      ImmediateTransaction.call do
        added_minutes = @variants.sum { |v| v.payable? ? v.duration_minutes : 0 }
        extend_appointment!(added_minutes) if added_minutes.positive?
        append_items!
        @appt.update!(total_price_cents: @appt.total_price_cents + @variants.sum { |v| price_for(v) })
        AuditLog.record!(auditable: @appt, action: "appointment.items_added", actor: @actor,
                         changes: { variant_ids: @variants.map(&:id) })
        @appt.reload
      end
    end

    private

    def extend_appointment!(minutes)
      service_end = @appt.service_ends_at + minutes.minutes
      finish = @appt.ends_at + minutes.minutes

      assert_coverage!(finish)
      assert_room_free!(finish)
      assert_staff_free!(finish)
      # Duration is derived from these two, so there is no counter to keep.
      @appt.update!(service_ends_at: service_end, ends_at: finish)
      # The denormalised copy drives the conflict query, so it moves too.
      @appt.appointment_staff.update_all(ends_at: finish) # rubocop:disable Rails/SkipsModelValidations
    end

    def assert_coverage!(finish)
      location = @appt.location
      date = @appt.starts_at.in_time_zone(location.tz).to_date
      covered = location.business_windows(date).any? { |w| @appt.starts_at >= w.first && finish <= w.last }
      raise Conflict, "outside_business_hours" unless covered

      service_ids = @variants.select(&:payable?).map(&:service_id)
      @appt.staff_profiles.each do |staff|
        raise Invalid, "therapist_not_qualified" unless staff.qualified_for?(service_ids)
        shifts = Shift.published.where(staff_profile: staff, location:, work_date: date).includes(:shift_breaks)
        shift = shifts.find { |s| s.covers?(@appt.starts_at, finish) }
        raise Conflict, "therapist_not_on_shift" unless shift && staff.status == "active"
        if shift.shift_breaks.any? { |b| b.starts_at < finish && b.ends_at > @appt.starts_at }
          raise Conflict, "therapist_on_break"
        end
      end
    end

    # Only the newly added tail is contested; the original span is already ours.
    def assert_room_free!(finish)
      clash = Appointment.active.overlapping(@appt.ends_at, finish)
                         .where(room_id: @appt.room_id).where.not(id: @appt.id).exists?
      blocked = RoomBlock.overlapping(@appt.ends_at, finish).exists?(room_id: @appt.room_id)
      raise Conflict, "slot_taken" if clash || blocked
    end

    def assert_staff_free!(finish)
      ids = @appt.staff_profiles.map(&:id)
      clash = AppointmentStaff.active.overlapping(@appt.ends_at, finish)
                              .where(staff_profile_id: ids)
                              .where.not(appointment_id: @appt.id).exists?
      raise Conflict, "therapist_unavailable" if clash
    end

    def append_items!
      next_position = @appt.appointment_items.maximum(:position).to_i + 1
      @variants.each_with_index do |v, i|
        @appt.appointment_items.create!(
          service_variant: v, kind: v.item_kind,
          duration_minutes: v.payable? ? v.duration_minutes : 0,
          price_cents: price_for(v), position: next_position + i
        )
      end
    end

    # BR-11: priced on the day it is added, at the appointment's location.
    def price_for(variant)
      Catalogue::ResolvePrice.call(
        variant:, location: @appt.location,
        on: @appt.starts_at.in_time_zone(@appt.location.tz).to_date
      )
    end
  end
end
