module Sales
  # BR-22: an order is paid only when payments + gift card redemptions +
  # membership credits + a held deposit cover the total.
  class SettleOrder < ApplicationService
    Unsettled = Class.new(StandardError)

    def initialize(order:, actor: nil)
      @order = order
      @actor = actor
    end

    def call
      ImmediateTransaction.call do
        @order.reload.recalculate!
        assert_visit_ready!
        outstanding = @order.outstanding_cents
        raise Unsettled, "outstanding_#{outstanding}" if outstanding.positive?

        apply_deposit!
        @order.update!(status: "paid", closed_at: Time.current, closed_by_user: @actor)
        # BR-17: completing the appointment is what generates earnings.
        Earnings::GenerateForAppointment.call(appointment: @order.appointment) if @order.appointment
        AuditLog.record!(auditable: @order, action: "order.settled", actor: @actor,
                         changes: { total_cents: @order.total_cents })
        @order
      end
    end

    private

    # A service order closes the visit, so the visit must be over and paid to
    # a real therapist — never to one only provisionally holding the slot.
    def assert_visit_ready!
      return unless @order.kind == "service" && @order.appointment

      appt = @order.appointment
      raise Unsettled, "appointment_not_completed" unless appt.status == "completed"
      raise Unsettled, "therapist_assignment_required" unless appt.staff_assignment_confirmed?
    end

    # The held deposit stops being the client's money here: it becomes a
    # payment on the order, in the method it was originally taken by.
    def apply_deposit!
      deposit = @order.held_deposit
      return unless deposit

      Payment.create!(
        order: @order, method: deposit.method, processing: "deposit",
        amount_cents: deposit.amount_cents, reference: "Deposit ##{deposit.id}",
        received_at: deposit.received_at, received_by_user: deposit.received_by_user
      )
      deposit.update!(status: "applied", applied_order: @order,
                      resolved_at: Time.current, resolved_by_user: @actor)
      AuditLog.record!(auditable: deposit, action: "deposit.applied", actor: @actor,
                       changes: { order: @order.number, amount_cents: deposit.amount_cents })
    end
  end
end
