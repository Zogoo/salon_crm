module Notifications
  # FRS §22. Email *and* SMS for confirmations, two reminders (24 h and 2 h),
  # the fee notice, and the rating request.
  #
  # Deliberately NOT sent: membership renewal reminders and cancellation-window
  # reminders. FRS §22 rules both out, so their absence is a decision.
  class Enqueue < ApplicationService
    # channel list per template — the rating link is SMS-only because FRS §11.2
    # specifies a text link.
    TEMPLATES = {
      "booking_confirmation"         => %w[email sms],
      "therapist_request_approved"   => %w[email sms],
      "therapist_request_rejected"   => %w[email sms],
      "appointment_reminder_24h"     => %w[email sms],
      "appointment_reminder_2h"      => %w[email sms],
      "fee_charged"                  => %w[email sms],
      "rating_request"               => %w[sms],
      "low_rating_alert"             => %w[email sms]
    }.freeze

    def initialize(template_key:, client: nil, user: nil, appointment: nil,
                   payload: {}, scheduled_for: nil)
      @template_key = template_key.to_s
      @client = client
      @user = user
      @appointment = appointment
      @payload = payload
      @scheduled_for = scheduled_for
    end

    def call
      channels = TEMPLATES.fetch(@template_key, [])
      recipient = @client || @user
      return [] if recipient.nil? || channels.empty?

      channels.filter_map do |channel|
        next if channel == "sms" && recipient.phone.blank?
        next if channel == "email" && recipient.try(:email).blank?

        # Unique index on (appointment, template, channel) makes this idempotent
        # even if a job runs twice.
        Notification.create!(
          recipient_type: recipient.class.name, recipient_id: recipient.id,
          channel:, template_key: @template_key, payload: @payload,
          appointment: @appointment, scheduled_for: @scheduled_for, status: "pending"
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
