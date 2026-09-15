module Notifications
  # Marks a queued notification as sent.
  #
  # Release 1 has no SMS account wired up, so delivery is recorded rather than
  # performed: the row, its payload and its timestamp are all real, and swapping
  # in Twilio and Action Mailer is a change to this one class. That keeps "did
  # the client get the reminder?" answerable now, and keeps the SMS bill at zero
  # until the account exists (doc 04 §10 puts it near $400/month at peak).
  #
  # The message is about the appointment as it is *now*: details are refreshed
  # at send time, and a reminder for a visit that no longer goes ahead is
  # skipped rather than sent.
  class Deliver < ApplicationService
    ABOUT_THE_VISIT = %w[booking_confirmation appointment_reminder_24h appointment_reminder_2h].freeze

    def initialize(notification:, now: Time.current)
      @notification = notification
      @now = now
    end

    def call
      appt = @notification.appointment
      if appt && ABOUT_THE_VISIT.include?(@notification.template_key)
        unless %w[pending_approval scheduled checked_in].include?(appt.status)
          @notification.update!(status: "skipped", error: "appointment #{appt.status}")
          return @notification
        end
        @notification.payload = @notification.payload.merge(Confirm.details_for(appt).stringify_keys)
      end

      @notification.update!(status: "sent", sent_at: @now,
                            provider_message_id: "recorded-#{@notification.id}")
      @notification
    end
  end
end
