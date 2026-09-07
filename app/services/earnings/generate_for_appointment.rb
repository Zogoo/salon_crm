module Earnings
  # BR-33. Pay is computed on the appointment's **total delivered duration**,
  # not per line:
  #
  #   * total lands on a ladder rung  -> ONE line at that rung
  #     (60-min massage + 30-min add-on = one 90-minute session)
  #   * total has no rung             -> one line per original item
  #     (120 + 30 = 150, which is not a rung, so a 120 and a 30)
  #
  # Then one line per therapist on the appointment (BR-34): a two-therapist
  # couples massage pays each of them a full session rate.
  #
  # This is a *pay* rule, not a pricing rule — the client is always charged per
  # menu item. Combining usually pays less than two separate lines would, which
  # is intended: one continuous 90-minute session is one 90-minute session.
  class GenerateForAppointment < ApplicationService
    LADDER = ServiceVariant::LADDER

    def initialize(appointment:)
      @appt = appointment
    end

    def call
      return [] unless @appt&.status == "completed"
      return [] if EarningLine.exists?(appointment_id: @appt.id, source: "session")

      items = @appt.appointment_items.payable.includes(:service_variant).order(:position).to_a
      return [] if items.empty?

      service_date = @appt.starts_at.in_time_zone(@appt.location.tz).to_date

      ImmediateTransaction.call do
        @appt.staff_profiles.flat_map do |therapist|
          buckets(items).filter_map { |b| line_for(therapist, b, service_date) }
        end
      end
    end

    private

    # The decomposition. Returns [{ duration_minutes:, covers_item_ids: }].
    def buckets(items)
      total = items.sum(&:duration_minutes)
      if LADDER.include?(total)
        [ { duration_minutes: total, covers_item_ids: items.map(&:id) } ]
      else
        items.map { |i| { duration_minutes: i.duration_minutes, covers_item_ids: [ i.id ] } }
      end
    end

    def line_for(therapist, bucket, service_date)
      rate = therapist.rate_cents_for(bucket[:duration_minutes], on: service_date)
      # A missing rung would silently pay zero; make it visible instead.
      return unless rate

      EarningLine.create!(
        staff_profile: therapist, location: @appt.location, service_date:,
        source: "session", appointment: @appt,
        covers_item_ids: bucket[:covers_item_ids],
        duration_minutes: bucket[:duration_minutes],
        quantity: 1, rate_cents: rate, amount_cents: rate
      )
    end
  end
end
