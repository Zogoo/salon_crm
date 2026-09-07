module Notifications
  # Marks a queued notification as sent.
  #
  # Release 1 has no SMS account wired up, so delivery is recorded rather than
  # performed: the row, its payload and its timestamp are all real, and swapping
  # in Twilio and Action Mailer is a change to this one class. That keeps "did
  # the client get the reminder?" answerable now, and keeps the SMS bill at zero
  # until the account exists (doc 04 §10 puts it near $400/month at peak).
  class Deliver < ApplicationService
    def initialize(notification:, now: Time.current)
      @notification = notification
      @now = now
    end

    def call
      @notification.update!(status: "sent", sent_at: @now,
                            provider_message_id: "recorded-#{@notification.id}")
      @notification
    end
  end
end
