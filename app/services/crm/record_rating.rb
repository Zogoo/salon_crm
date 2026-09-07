module Crm
  # FRS §11.2 / BR-45, BR-45a.
  class RecordRating < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(appointment:, score:, channel:, feedback: nil, improvement: nil,
                   would_recommend: nil, now: Time.current)
      @appt = appointment
      @score = score.to_i
      @channel = channel.to_s
      @feedback = feedback
      @improvement = improvement
      @would_recommend = would_recommend
      @now = now
    end

    def call
      raise Invalid, "already_rated" if AppointmentRating.exists?(appointment_id: @appt.id)
      raise Invalid, "score must be 1-10" unless (1..10).cover?(@score)

      ImmediateTransaction.call do
        rating = AppointmentRating.create!(
          appointment: @appt,
          staff_profile: @appt.staff_profiles.first,
          score: @score, feedback: @feedback, improvement: @improvement,
          would_recommend: @would_recommend, channel: @channel, submitted_at: @now
        )
        alert!(rating)
        rating
      end
    end

    private

    # BR-45a: **below** the threshold — 1–5 by default, so a 6 does not alert.
    def alert!(rating)
      threshold = @appt.location.low_rating_alert_below
      return unless rating.low?(threshold)

      payload = { score: rating.score, reference: @appt.reference,
                  therapist: rating.staff_profile.display_name,
                  location: @appt.location.name }

      # Owner and that location's Manager, both.
      recipients = User.where(role: "owner")
                       .or(User.where(role: "manager", location_id: @appt.location_id))
      recipients.find_each do |user|
        Notifications::Enqueue.call(template_key: "low_rating_alert", user:,
                                    appointment: @appt, payload:)
      end
    end
  end
end
