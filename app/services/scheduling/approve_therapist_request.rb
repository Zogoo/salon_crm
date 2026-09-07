module Scheduling
  # BR-15a. Approval moves the held appointment to `scheduled`; rejection frees
  # the slot immediately and records no fee against the client.
  class ApproveTherapistRequest < ApplicationService
    def initialize(request:, actor:, decision: :approve, note: nil, now: Time.current)
      @request = request
      @actor = actor
      @decision = decision.to_sym
      @note = note
      @now = now
    end

    def call
      ImmediateTransaction.call do
        @decision == :approve ? approve! : reject!
      end
    end

    private

    def approve!
      appt = @request.appointment
      # Re-check before granting: the one thing that can change under a held
      # slot is someone editing the shift.
      unless still_bookable?(appt)
        @request.update!(status: "escalated", reviewed_at: @now,
                         note: "therapist no longer has a covering shift")
        return @request
      end

      TransitionStatus.call(appointment: appt, to: "scheduled", actor: @actor,
                            reason: "therapist_request_approved")
      @request.update!(status: "approved", reviewed_by_user: @actor, reviewed_at: @now)
      @request
    end

    def reject!
      TransitionStatus.call(appointment: @request.appointment, to: "cancelled",
                            actor: @actor, reason: "therapist_request_rejected")
      @request.update!(status: "rejected", reviewed_by_user: @actor,
                       reviewed_at: @now, note: @note)
      @request
    end

    def still_bookable?(appt)
      Shift.published
           .where(staff_profile_id: @request.requested_staff_profile_id,
                  location_id: appt.location_id)
           .overlapping(appt.starts_at, appt.ends_at)
           .any? { |s| s.covers?(appt.starts_at, appt.ends_at) }
    end
  end
end
