module Scheduling
  # Doc 03 §4.6. A reschedule is a new booking followed by releasing the old
  # one, inside one transaction — never a mutation of starts_at.
  #
  # Two reasons. The chain is preserved for the no-show and retention reports,
  # and moving an appointment in place would momentarily conflict with itself
  # while the new interval overlaps the old.
  class RescheduleAppointment < ApplicationService
    def initialize(appointment:, start_at:, actor: nil, staff_profile_ids: nil, room_id: nil)
      @appt = appointment
      @start_at = start_at
      @actor = actor
      @staff_profile_ids = staff_profile_ids
      @room_id = room_id
    end

    def call
      raise BookAppointment::Invalid, "cannot_reschedule_#{@appt.status}" unless reschedulable?

      ImmediateTransaction.call do
        # Release first, so the appointment does not collide with itself when
        # the new time overlaps the old.
        TransitionStatus.call(appointment: @appt, to: "cancelled", actor: @actor,
                              reason: "rescheduled", rescheduling: true)

        BookAppointment.call(
          location: @appt.location, client: @appt.client, actor: @actor,
          variant_ids: @appt.appointment_items.map(&:service_variant_id),
          start_at: @start_at,
          staff_profile_ids: @staff_profile_ids || @appt.staff_profiles.map(&:id),
          room_id: @room_id,
          booking_channel: @appt.booking_channel,
          client_note: @appt.client_note,
          appointment_note: @appt.appointment_note,
          participant_client_ids: @appt.appointment_participants.map(&:client_id) - [ @appt.client_id ]
        ).tap { |fresh| fresh.update!(rescheduled_from: @appt) }
      end
    end

    private

    def reschedulable? = %w[pending_approval scheduled checked_in].include?(@appt.status)
  end
end
