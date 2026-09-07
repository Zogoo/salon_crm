module Sales
  # BR-19, Release 1 behaviour (doc 08 §2): the fee is *calculated and recorded
  # as owed*, not charged — there is no gateway. It becomes an open `Fee` order
  # visible on the client profile. The front desk is deliberately not warned at
  # the next booking (OQ-11).
  class ChargeCancellationFee < ApplicationService
    def initialize(appointment:, actor: nil)
      @appt = appointment
      @actor = actor
    end

    def call
      return nil unless @appt.fee_charged_cents.positive?
      return nil if Order.exists?(appointment_id: @appt.id, kind: "fee")

      ImmediateTransaction.call do
        order = Order.create!(
          number: Order.generate_number, client: @appt.client, location: @appt.location,
          appointment: @appt, kind: "fee", status: "open", opened_by_user: @actor
        )
        OrderLineItem.create!(
          order:, description: fee_description,
          quantity: 1, unit_price_cents: @appt.fee_charged_cents,
          line_total_cents: @appt.fee_charged_cents,
          revenue_category: "fee"          # neither revenue nor liability — BR-48
        )
        order.recalculate!
        Notifications::Enqueue.call(
          template_key: "fee_charged", client: @appt.client, appointment: @appt,
          payload: { amount_cents: @appt.fee_charged_cents, reference: @appt.reference }
        )
        order
      end
    end

    private

    def fee_description
      label = @appt.status == "no_show" ? "No-show" : "Late cancellation"
      "#{label} fee — #{@appt.reference}"
    end
  end
end
