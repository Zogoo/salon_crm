module Crm
  # BR-44: append-only. A correction is a new note that supersedes the original,
  # never an edit.
  class RecordCareNote < ApplicationService
    Forbidden = Class.new(StandardError)

    def initialize(appointment:, staff_profile:, body:, supersedes: nil)
      @appt = appointment
      @staff = staff_profile
      @body = body
      @supersedes = supersedes
    end

    def call
      # Only a therapist on this appointment may write its care note.
      unless @appt.appointment_staff.exists?(staff_profile_id: @staff.id)
        raise Forbidden, "not_assigned_to_this_appointment"
      end

      CareNote.create!(appointment: @appt, staff_profile: @staff,
                       body: @body, supersedes_note: @supersedes)
    end
  end
end
