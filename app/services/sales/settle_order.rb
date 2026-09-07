module Sales
  # BR-22: an order is paid only when payments + gift card redemptions +
  # membership credits cover the total.
  class SettleOrder < ApplicationService
    Unsettled = Class.new(StandardError)

    def initialize(order:, actor: nil)
      @order = order
      @actor = actor
    end

    def call
      ImmediateTransaction.call do
        @order.reload.recalculate!
        outstanding = @order.outstanding_cents
        raise Unsettled, "outstanding_#{outstanding}" if outstanding.positive?

        @order.update!(status: "paid", closed_at: Time.current, closed_by_user: @actor)
        # BR-17: completing the appointment is what generates earnings.
        Earnings::GenerateForAppointment.call(appointment: @order.appointment) if @order.appointment
        AuditLog.record!(auditable: @order, action: "order.settled", actor: @actor,
                         changes: { total_cents: @order.total_cents })
        @order
      end
    end
  end
end
