module Scheduling
  # The mirror of AddAppointmentItem. Removing an add-on shortens the
  # appointment, which can never create a conflict, so there is nothing to
  # re-check — but the service line, the total and the end time all move
  # together, and the last remaining service line may not be removed.
  class RemoveAppointmentItem < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(appointment:, item_id:, actor: nil)
      @appt = appointment
      @item_id = item_id
      @actor = actor
    end

    def call
      raise Invalid, "cannot_edit_#{@appt.status}" unless AddAppointmentItem::EDITABLE.include?(@appt.status)

      item = @appt.appointment_items.find(@item_id)
      raise Invalid, "cannot_remove_service" if item.kind == "service"

      ImmediateTransaction.call do
        minutes = item.duration_minutes
        price = item.price_cents
        item.destroy!

        if minutes.positive?
          @appt.update!(service_ends_at: @appt.service_ends_at - minutes.minutes,
                        ends_at: @appt.ends_at - minutes.minutes)
          @appt.appointment_staff.update_all(ends_at: @appt.ends_at) # rubocop:disable Rails/SkipsModelValidations
        end
        @appt.update!(total_price_cents: @appt.total_price_cents - price)
        deposit = Deposit.held.find_by(appointment_id: @appt.id)
        raise Invalid, "price_below_deposit" if deposit && @appt.total_price_cents < deposit.amount_cents

        AuditLog.record!(auditable: @appt, action: "appointment.item_removed", actor: @actor,
                         changes: { item_id: @item_id })
        Sales::SyncOrder.call(appointment: @appt.reload)
        @appt.reload
      end
    end
  end
end
