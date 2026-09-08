module Reporting
  # Doc 05 §13 / doc 01 §5. New vs returning, frequency, lapsed clients and
  # lifetime value.
  class ClientRetention < ApplicationService
    LAPSED_AFTER = 90 # days without a completed visit

    def initialize(location_ids:, from:, to:, now: Time.current)
      @location_ids = Array(location_ids)
      @from = from.to_date
      @to = to.to_date
      @now = now
    end

    def call
      visits = Appointment.where(location_id: @location_ids, status: "completed")
                          .includes(:client)
      in_period = visits.where(starts_at: window).to_a
      by_client = in_period.group_by(&:client)

      first_visit = visits.group(:client_id).minimum(:starts_at)
      new_clients = by_client.keys.select { |c| within_period?(first_visit[c.id]) }

      {
        from: @from, to: @to,
        clients_seen: by_client.size,
        new_clients: new_clients.size,
        returning_clients: by_client.size - new_clients.size,
        visits: in_period.size,
        average_visits_per_client: by_client.any? ? (in_period.size.to_f / by_client.size).round(2) : 0.0,
        lapsed: lapsed(visits),
        top_clients: by_client.map { |client, appts|
          { client_id: client.id, full_name: client.full_name, visits: appts.size,
            spend_cents: appts.sum(&:total_price_cents) }
        }.sort_by { |r| -r[:spend_cents] }.first(10)
      }
    end

    private

    def window
      tz = Location.where(id: @location_ids).first&.tz || Time.zone
      tz.local(@from.year, @from.month, @from.day).beginning_of_day..
        tz.local(@to.year, @to.month, @to.day).end_of_day
    end

    def within_period?(time) = time.present? && window.cover?(time)

    # Seen before, but not in the last 90 days — the win-back list.
    def lapsed(visits)
      last_visit = visits.group(:client_id).maximum(:starts_at)
      cutoff = @now - LAPSED_AFTER.days
      stale = last_visit.select { |_, seen| seen < cutoff }
      { after_days: LAPSED_AFTER, count: stale.size,
        client_ids: stale.keys.first(50) }
    end
  end
end
