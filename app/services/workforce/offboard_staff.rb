module Workforce
  # BR-02: offboarding is soft — historical earnings, care notes and
  # appointments back past payouts and client care, so nothing is deleted.
  #
  # It is *blocked* while future appointments exist, rather than warned about.
  # Doc 01 §3.2 calls this the single most common source of operational chaos
  # in salon systems: a terminated therapist still on next week's schedule.
  class OffboardStaff < ApplicationService
    Blocked = Class.new(StandardError)

    def initialize(staff_profile:, actor:, termination_date: Date.current, now: Time.current)
      @profile = staff_profile
      @actor = actor
      @termination_date = termination_date.to_date
      @now = now
    end

    def call
      conflicts = future_appointments
      raise Blocked, conflicts.map(&:appointment_id).join(",") if conflicts.any?

      ImmediateTransaction.call do
        Shift.where(staff_profile_id: @profile.id)
             .where("work_date > ?", @termination_date).destroy_all
        @profile.update!(status: "terminated", termination_date: @termination_date)
        @profile.user.update!(status: "disabled")
        AuditLog.record!(auditable: @profile, action: "staff.offboarded", actor: @actor,
                         changes: { termination_date: @termination_date.to_s })
        @profile
      end
    end

    private

    # Work still to be done — not everything that occupies a slot. A completed
    # appointment cannot be reassigned or cancelled, so it is no reason to keep
    # a leaver on the books; BR-02 is about next week's schedule.
    OUTSTANDING = %w[pending_approval scheduled checked_in in_progress].freeze

    def future_appointments
      AppointmentStaff.where(staff_profile_id: @profile.id, status: OUTSTANDING)
                      .where("starts_at > ?", @termination_date.end_of_day)
                      .to_a
    end
  end
end
