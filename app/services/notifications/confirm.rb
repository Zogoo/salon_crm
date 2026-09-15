module Notifications
  # FRS §22: an email and an SMS confirmation, then two reminders at 24 h and
  # 2 h before the start.
  #
  # Called both when Owner/Manager books directly and when a therapist request
  # is approved, so the client is confirmed exactly once either way.
  class Confirm < ApplicationService
    def initialize(appointment:)
      @appt = appointment
    end

    def call
      Enqueue.call(template_key: "booking_confirmation", client: @appt.client,
                   appointment: @appt, payload: self.class.details_for(@appt))

      @appt.location.reminder_offsets_minutes.each do |minutes|
        key = minutes >= 1440 ? "appointment_reminder_24h" : "appointment_reminder_2h"
        Enqueue.call(template_key: key, client: @appt.client, appointment: @appt,
                     payload: self.class.details_for(@appt),
                     scheduled_for: @appt.starts_at - minutes.minutes)
      end
    end

    # What a client-facing message says about the visit. Read again at send
    # time (Deliver), because a reminder queued at booking must reflect a later
    # move or therapist assignment. A therapist only provisionally holding a
    # no-preference slot is never named.
    def self.details_for(appt)
      {
        reference: appt.reference,
        starts_at: appt.starts_at.in_time_zone(appt.location.tz).iso8601,
        location: appt.location.name,
        therapist: appt.staff_assignment_confirmed? ? appt.staff_profiles.map(&:display_name).join(", ") : nil
      }
    end
  end
end
