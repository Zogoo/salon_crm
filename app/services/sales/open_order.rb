module Sales
  # Opens the checkout for an appointment, priced from the snapshot taken at
  # booking (BR-11) rather than from today's menu.
  #
  # Re-opening returns the same order, refreshed from the appointment while no
  # money has been taken against it — so a discount given from the calendar
  # before the visit never leaves the bill out of step with what was delivered.
  class OpenOrder < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(appointment:, actor: nil)
      @appt = appointment
      @actor = actor
    end

    def call
      existing = Order.find_by(appointment_id: @appt.id, kind: "service")
      if existing
        return existing if existing.money_taken?

        return SyncOrder.call(appointment: @appt, order: existing)
      end

      raise Invalid, "appointment_not_active" unless @appt.active?

      ImmediateTransaction.call do
        order = Order.create!(
          number: Order.generate_number, client: @appt.client, location: @appt.location,
          appointment: @appt, kind: "service", opened_by_user: @actor
        )
        SyncOrder.build_lines!(order, @appt)
        order.recalculate!
      end
    end
  end
end
