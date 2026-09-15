module Scheduling
  # BR-21: a status transition is the only way to release a room and therapist.
  # BR-18/BR-19: the 4-hour window decides cancelled vs late_cancelled, and a
  # late cancel or no-show records a 20% fee as *owed* — Release 1 has no
  # gateway, so nothing is charged (doc 08 §1). A deposit held for the visit
  # pays that fee first, and the rest of it goes back to the client.
  class TransitionStatus < ApplicationService
    Invalid = Class.new(StandardError)

    ALLOWED = {
      "pending_approval" => %w[scheduled cancelled],
      "scheduled"        => %w[checked_in cancelled late_cancelled no_show],
      "checked_in"       => %w[in_progress cancelled no_show],
      "in_progress"      => %w[completed],
      "completed"        => [],
      "cancelled"        => [],
      "late_cancelled"   => [],
      "no_show"          => []
    }.freeze

    RELEASED = %w[cancelled late_cancelled no_show].freeze

    # `rescheduling:` marks the release half of a move (doc 03 §4.6). The
    # client is keeping their appointment, so none of the machinery that exists
    # to record a client giving up a slot applies: no late-cancel
    # reclassification, no fee, no counter against the client, and the deposit
    # and any open order travel with the booking instead of being released.
    def initialize(appointment:, to:, actor: nil, reason: nil, now: Time.current,
                   rescheduling: false)
      @appt = appointment
      @to = to.to_s
      @actor = actor
      @reason = reason
      @now = now
      @rescheduling = rescheduling
    end

    def call
      from = @appt.status
      target = resolve_target(from)
      unless ALLOWED.fetch(from, []).include?(target)
        raise Invalid, "cannot move from #{from} to #{target}"
      end
      # BR-32/BR-34: a no-preference booking holds a provisional therapist.
      # Completing it would pay, credit and rate that therapist for work
      # someone else may have done.
      if target == "completed" && !@appt.staff_assignment_confirmed?
        raise Invalid, "therapist_assignment_required"
      end

      ImmediateTransaction.call do
        release_order!(target)
        apply_fee!(target)
        @appt.update!(status: target, **cancellation_fields(target))
        # Keep the denormalised copy in step, or the conflict query goes wrong.
        @appt.appointment_staff.update_all(status: target)
        bump_client_counters!(target)
        AppointmentStatusEvent.create!(
          appointment: @appt, from_status: from, to_status: target,
          actor_user: @actor, occurred_at: @now, reason: @reason
        )
        close_approval_request!(from, target)
        after_transition!(target)
        @appt
      end
    end

    private

    # A cancellation inside the window is a late cancellation, whatever the
    # caller asked for.
    def resolve_target(_from)
      return @to unless @to == "cancelled"
      return @to if @rescheduling

      hours = @appt.location.cancellation_window_hours
      @now > (@appt.starts_at - hours.hours) ? "late_cancelled" : "cancelled"
    end

    def cancellation_fields(target)
      return {} unless RELEASED.include?(target)
      { cancelled_at: @now, cancellation_reason: @reason }
    end

    def apply_fee!(target)
      percent =
        case target
        when "no_show"        then @appt.location.no_show_fee_percent
        when "late_cancelled" then @appt.location.late_cancel_fee_percent
        end
      return unless percent
      @appt.fee_charged_cents = (@appt.total_price_cents * percent / 100.0).round
    end

    # BR-15a: a request is about *this* appointment. Once the appointment is
    # no longer waiting, the request must not stay pending — it would sit on
    # the Approvals screen forever and trip the auto-approval job.
    def close_approval_request!(from, target)
      return unless from == "pending_approval" && target != "scheduled"

      ApprovalRequest.pending.where(appointment_id: @appt.id)
                     .update_all(status: "withdrawn", reviewed_at: @now, updated_at: @now)
    end

    # An order opened early (a calendar discount) is voided with the visit, as
    # long as no money was taken against it; if it was, the refund has to be
    # dealt with first.
    def release_order!(target)
      return if @rescheduling || !RELEASED.include?(target)

      order = Order.find_by(appointment_id: @appt.id, kind: "service")
      return unless order
      raise Sales::OrderLocked, "order_has_payments" if order.money_taken?

      order.update!(status: "voided", closed_at: @now, closed_by_user: @actor)
    end

    # Side effects that belong to a status change rather than to a screen.
    def after_transition!(target)
      case target
      when "scheduled"
        confirm!
      when "completed"
        Earnings::GenerateForAppointment.call(appointment: @appt)
        request_rating!
      when "no_show", "late_cancelled"
        # BR-19: recorded as owed, not charged — Release 1 has no gateway.
        fee_order = Sales::ChargeCancellationFee.call(appointment: @appt, actor: @actor)
        Sales::ReleaseDeposit.call(appointment: @appt, actor: @actor, fee_order:, reason: target)
      when "cancelled"
        return if @rescheduling

        Sales::ReleaseDeposit.call(appointment: @appt, actor: @actor, reason: @reason || "cancelled")
      end
    end

    def confirm!
      Notifications::Confirm.call(appointment: @appt)
    end

    # FRS §11.2: the desk usually asks for the score before checkout. A client
    # who has already answered is not texted to answer again.
    def request_rating!
      return if AppointmentRating.exists?(appointment_id: @appt.id)

      Notifications::Enqueue.call(
        template_key: "rating_request", client: @appt.client, appointment: @appt,
        payload: { token: @appt.ensure_rating_token!,
                   therapist: @appt.staff_profiles.first&.display_name }
      )
    end

    def bump_client_counters!(target)
      return if @rescheduling

      column = { "no_show" => :no_show_count,
                 "late_cancelled" => :late_cancel_count,
                 "cancelled" => :cancel_count }[target]
      return unless column
      Client.where(id: @appt.client_id).update_counters(column => 1)
    end
  end
end
