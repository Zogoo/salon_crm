module Reporting
  # FRS §9. Every completed appointment for a date: time, client, therapist,
  # service, length, price, tip, total paid, method.
  class ClientLog < ApplicationService
    def initialize(location:, date:)
      @location = location
      @date = date.to_date
    end

    def call
      Appointment.on_date(@location, @date)
                 .where(status: "completed")
                 .includes(:client, :room, :appointment_items, :staff_profiles,
                           order: %i[payments tip_allocations])
                 .order(:starts_at)
                 .map { |appt| row(appt) }
    end

    private

    def row(appt)
      order = appt.order
      {
        appointment_id: appt.id,
        reference: appt.reference,
        time: appt.starts_at.in_time_zone(@location.tz).strftime("%H:%M"),
        client_name: appt.client.full_name,
        therapists: appt.staff_profiles.map(&:display_name),
        services: appt.appointment_items.map { |i| i.service_variant.name },
        duration_minutes: appt.duration_minutes,
        service_price_cents: appt.total_price_cents,
        tip_cents: order&.tip_cents || 0,
        total_paid_cents: order&.paid_cents || 0,
        payment_methods: order&.payments&.captured&.map(&:method)&.uniq || []
      }
    end
  end
end
