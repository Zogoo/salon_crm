module Crm
  # BR-46 / FRS §12. The one-glance answer to "who is this on the phone?" —
  # visits, spend, who and what they usually book, and how reliable they are.
  class ClientHistorySummary < ApplicationService
    def initialize(client:)
      @client = client
    end

    def call
      completed = @client.appointments.where(status: "completed")
                          .includes(:staff_profiles, :location, appointment_items: { service_variant: :service })

      {
        client_id: @client.id,
        visits: completed.size,
        # BR-17: only completed appointments are revenue, so only they count.
        lifetime_spend_cents: completed.sum(&:total_price_cents),
        first_visit: local_date(completed.min_by(&:starts_at)),
        last_visit: local_date(last = completed.max_by(&:starts_at)),
        days_since_last_visit: days_since(last),
        favourite_service: most_common(completed.flat_map { |a| a.appointment_items.map { |i| i.service_variant.name } }),
        favourite_therapist: most_common(completed.flat_map { |a| a.staff_profiles.map(&:display_name) }),
        no_show_count: @client.no_show_count,
        late_cancel_count: @client.late_cancel_count,
        cancel_count: @client.cancel_count
      }
    end

    private

    def days_since(appt)
      return nil if appt.nil?
      # The salon's today, not the server's — see Location#today.
      (appt.location.today - appt.starts_at.in_time_zone(appt.location.tz).to_date).to_i
    end

    def local_date(appt)
      appt && appt.starts_at.in_time_zone(appt.location.tz).to_date
    end

    def most_common(values)
      return nil if values.empty?
      values.tally.max_by { |_, count| count }.first
    end
  end
end
