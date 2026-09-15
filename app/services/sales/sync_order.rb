module Sales
  # Keeps a service order's lines in step with its appointment.
  #
  # An order can exist before the visit is over — the desk may give a discount
  # from the calendar — and the appointment can still change afterwards (an
  # add-on, a different service, a move). The appointment is the source of what
  # was delivered, so its lines are rebuilt from it; lines added by hand at the
  # desk and discounts are kept.
  #
  # Refuses once money has been taken, because re-pricing a bill that has
  # already been part-paid is exactly what BR-22/BR-23 forbid.
  class SyncOrder < ApplicationService
    def initialize(appointment:, order: nil)
      @appt = appointment
      @order = order
    end

    def call
      order = @order || Order.find_by(appointment_id: @appt.id, kind: "service")
      return nil unless order

      ImmediateTransaction.call do
        raise OrderLocked, "order_has_payments" if order.money_taken?

        order.order_line_items.where(purchasable_type: "ServiceVariant").delete_all
        self.class.build_lines!(order, @appt)
        order.recalculate!
        raise OrderLocked, "discount_exceeds_order" if order.discount_cents > order.subtotal_cents

        order
      end
    end

    # BR-11: priced from the snapshot on the appointment, never today's menu.
    def self.build_lines!(order, appointment)
      staff = appointment.staff_assignment_confirmed? ? appointment.staff_profiles.first : nil
      appointment.appointment_items.includes(:service_variant).order(:position).each do |item|
        OrderLineItem.create!(
          order:, purchasable: item.service_variant,
          description: item.service_variant.name,
          quantity: 1, unit_price_cents: item.price_cents,
          line_total_cents: item.price_cents,
          revenue_category: item.kind,          # service | add_on | enhancement
          staff_profile: staff
        )
      end
    end
  end
end
