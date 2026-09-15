module Scheduling
  # Doc 03 §4.6. A reschedule is a new booking followed by releasing the old
  # one, inside one transaction — never a mutation of starts_at.
  #
  # Two reasons. The chain is preserved for the no-show and retention reports,
  # and moving an appointment in place would momentarily conflict with itself
  # while the new interval overlaps the old.
  #
  # Everything that belongs to the client's visit rather than to the slot moves
  # with it: a therapist request still waiting for approval (BR-15), the
  # deposit, and an order opened early for a discount.
  class RescheduleAppointment < ApplicationService
    def initialize(appointment:, start_at:, actor: nil, staff_profile_ids: nil, room_id: nil,
                   variant_ids: nil)
      @appt = appointment
      @start_at = start_at
      @actor = actor
      @staff_profile_ids = staff_profile_ids
      @room_id = room_id
      @variant_ids = variant_ids
    end

    def call
      raise BookAppointment::Invalid, "cannot_reschedule_#{@appt.status}" unless reschedulable?

      ImmediateTransaction.call do
        pending_request = @appt.status == "pending_approval" ? ApprovalRequest.pending.find_by(appointment_id: @appt.id) : nil
        order = Order.find_by(appointment_id: @appt.id, kind: "service")
        raise Sales::OrderLocked, "order_has_payments" if order&.money_taken?

        # Release first, so the appointment does not collide with itself when
        # the new time overlaps the old.
        TransitionStatus.call(appointment: @appt, to: "cancelled", actor: @actor,
                              reason: "rescheduled", rescheduling: true)

        fresh = BookAppointment.call(
          location: @appt.location, client: @appt.client, actor: @actor,
          variant_ids: @variant_ids || @appt.appointment_items.map(&:service_variant_id),
          start_at: @start_at,
          staff_profile_ids: resolved_staff_ids,
          requested_staff_profile_id: pending_request&.requested_staff_profile_id,
          room_id: @room_id,
          booking_channel: @appt.booking_channel,
          client_note: @appt.client_note,
          appointment_note: @appt.appointment_note,
          participant_client_ids: @appt.appointment_participants.map(&:client_id) - [ @appt.client_id ]
        )
        fresh.update!(rescheduled_from: @appt)
        carry_request_clock!(fresh, pending_request)
        carry_deposit!(fresh)
        carry_order!(fresh, order)
        fresh
      end
    end

    private

    def resolved_staff_ids
      return @staff_profile_ids unless @staff_profile_ids.nil?
      return nil unless @appt.staff_assignment_confirmed?

      @appt.staff_profiles.map(&:id)
    end

    # BR-15a counts 45 minutes from when the client asked, not from the move,
    # so moving a request never pushes its auto-approval back.
    def carry_request_clock!(fresh, pending_request)
      return unless pending_request

      ApprovalRequest.where(appointment_id: fresh.id)
                     .update_all(created_at: pending_request.created_at)
    end

    def carry_deposit!(fresh)
      deposit = Deposit.held.find_by(appointment_id: @appt.id)
      return unless deposit
      raise BookAppointment::Invalid, "price_below_deposit" if fresh.total_price_cents < deposit.amount_cents

      deposit.update!(appointment: fresh)
    end

    def carry_order!(fresh, order)
      return unless order

      order.update!(appointment: fresh)
      Sales::SyncOrder.call(appointment: fresh, order:)
    end

    def reschedulable? = %w[pending_approval scheduled checked_in].include?(@appt.status)
  end
end
