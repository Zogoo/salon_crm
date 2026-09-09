module Workforce
  # BR-05: staff never self-edit a shift — a change is a request someone
  # approves. BR-06: a *location* change may be approved only by the Owner,
  # which is the one approval the Owner explicitly withheld from Managers.
  class ApproveStaffRequest < ApplicationService
    Forbidden = Class.new(StandardError)
    Invalid   = Class.new(StandardError)

    def initialize(request:, actor:, decision: :approve, note: nil, now: Time.current)
      @request = request
      @actor = actor
      @decision = decision.to_sym
      @note = note
      @now = now
    end

    def call
      raise Invalid, "already_reviewed" unless @request.status == "submitted"
      assert_permitted!

      ImmediateTransaction.call do
        @decision == :approve ? approve! : reject!
      end
    end

    private

    def assert_permitted!
      return if @actor.owner?
      # A Manager may approve a shift change at their own location, never a
      # location change.
      raise Forbidden, "owner_approval_required" if @request.kind == "location_change"
      raise Forbidden, "forbidden" unless @actor.manager? &&
                                          @actor.location_id == @request.staff_profile.location_id
    end

    def approve!
      case @request.kind
      when "shift_change"    then apply_shift_change!
      when "location_change" then apply_location_change!
      end
      finish!("approved")
    end

    def reject! = finish!("rejected")

    def finish!(status)
      @request.update!(status:, reviewed_by_user: @actor, reviewer_role: @actor.role,
                       reviewed_at: @now, review_note: @note)
      AuditLog.record!(auditable: @request, action: "staff_request.#{status}", actor: @actor,
                       changes: { kind: @request.kind })
      @request
    end

    def apply_shift_change!
      shift = @request.shift
      raise Invalid, "shift_missing" unless shift
      payload = @request.requested_payload

      tz = shift.location.tz
      date = payload["work_date"].present? ? Date.parse(payload["work_date"]) : shift.work_date
      starts = payload["starts_at"].present? ? tz.parse("#{date} #{payload['starts_at']}") : shift.starts_at
      ends   = payload["ends_at"].present?   ? tz.parse("#{date} #{payload['ends_at']}")   : shift.ends_at

      assert_no_orphans!(shift, starts, ends)
      shift.update!(work_date: date, starts_at: starts, ends_at: ends)
    end

    # BR-07: never shorten a shift out from under a booked appointment.
    def assert_no_orphans!(shift, starts, ends)
      orphans = Scheduling::ShiftCoverage.orphaned_by_change(shift, starts_at: starts, ends_at: ends)
      return if orphans.empty?

      raise Invalid, "would_orphan_appointments:#{Scheduling::ShiftCoverage.appointment_ids(orphans).join(',')}"
    end

    # BR-03a: a location change *moves* the therapist rather than adding a
    # second location, so future shifts at the old location would become
    # unreachable — and a booked appointment must never be silently orphaned.
    def apply_location_change!
      profile = @request.staff_profile
      destination = Location.find(@request.requested_payload.fetch("location_id"))

      booked = AppointmentStaff.active.where(staff_profile_id: profile.id)
                               .where("starts_at >= ?", @now)
      raise Invalid, "has_future_appointments" if booked.exists?

      Shift.where(staff_profile_id: profile.id).where("starts_at >= ?", @now).destroy_all
      profile.update!(location: destination)
    end
  end
end
