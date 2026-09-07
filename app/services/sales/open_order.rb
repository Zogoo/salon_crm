module Sales
  # Opens the checkout for a completed appointment, priced from the snapshot
  # taken at booking (BR-11) rather than from today's menu.
  class OpenOrder < ApplicationService
    def initialize(appointment:, actor: nil)
      @appt = appointment
      @actor = actor
    end

    def call
      existing = Order.find_by(appointment_id: @appt.id)
      return existing if existing

      ImmediateTransaction.call do
        order = Order.create!(
          number: Order.generate_number, client: @appt.client, location: @appt.location,
          appointment: @appt, kind: "service", opened_by_user: @actor
        )
        @appt.appointment_items.order(:position).each do |item|
          OrderLineItem.create!(
            order:, purchasable: item.service_variant,
            description: item.service_variant.name,
            quantity: 1, unit_price_cents: item.price_cents,
            line_total_cents: item.price_cents,
            revenue_category: item.kind,          # service | add_on | enhancement
            staff_profile: @appt.staff_profiles.first
          )
        end
        order.recalculate!
      end
    end
  end
end
