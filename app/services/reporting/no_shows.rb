module Reporting
  # FRS §21 / doc 05 §13. No-show and late-cancel rates by therapist, weekday
  # and channel, plus the fees they generated — which in Release 1 are owed
  # rather than collected, so the report shows both.
  class NoShows < ApplicationService
    def initialize(location_ids:, from:, to:)
      @location_ids = Array(location_ids)
      @from = from.to_date
      @to = to.to_date
    end

    def call
      appts = Appointment.where(location_id: @location_ids)
                         .where(starts_at: window)
                         .includes(:location, :staff_profiles)

      total = appts.size
      no_shows = appts.select { |a| a.status == "no_show" }
      late = appts.select { |a| a.status == "late_cancelled" }
      # Tie the fees to the appointments this report is about, not to when the
      # fee order happened to be written — a no-show is marked whenever someone
      # notices, which is rarely the appointment's own date.
      fee_orders = Order.where(kind: "fee",
                               appointment_id: (no_shows + late).map(&:id))

      {
        from: @from, to: @to, appointments: total,
        no_shows: no_shows.size, late_cancellations: late.size,
        no_show_rate: rate(no_shows.size, total),
        late_cancel_rate: rate(late.size, total),
        fees_owed_cents: fee_orders.where(status: "open").sum(:total_cents),
        fees_collected_cents: fee_orders.where(status: "paid").sum(:total_cents),
        by_weekday: (no_shows + late).group_by { |a| a.starts_at.in_time_zone(a.location.tz).strftime("%A") }
                                     .transform_values(&:size),
        by_therapist: (no_shows + late).flat_map { |a| a.staff_profiles.map(&:display_name) }
                                       .tally.sort_by { |_, n| -n }.to_h,
        by_channel: (no_shows + late).group_by(&:booking_channel).transform_values(&:size)
      }
    end

    private

    def window
      tz = Location.where(id: @location_ids).first&.tz || Time.zone
      tz.local(@from.year, @from.month, @from.day).beginning_of_day..
        tz.local(@to.year, @to.month, @to.day).end_of_day
    end

    def rate(part, whole) = whole.zero? ? 0.0 : (part.to_f / whole * 100).round(1)
  end
end
