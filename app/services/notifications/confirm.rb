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
                   appointment: @appt, payload: payload)

      @appt.location.reminder_offsets_minutes.each do |minutes|
        key = minutes >= 1440 ? "appointment_reminder_24h" : "appointment_reminder_2h"
        Enqueue.call(template_key: key, client: @appt.client, appointment: @appt,
                     payload: payload, scheduled_for: @appt.starts_at - minutes.minutes)
      end
    end

    private

    def payload
      {
        reference: @appt.reference,
        starts_at: @appt.starts_at.in_time_zone(@appt.location.tz).iso8601,
        location: @appt.location.name,
        therapist: @appt.staff_profiles.map(&:display_name).join(", ")
      }
    end
  end
end
