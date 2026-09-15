module Scheduling
  # Creates a finite set of weekly repeats atomically. If any future date is
  # unavailable, none are created — and the error names every date that failed
  # and why, so the desk can shorten the series (typically to the published
  # roster) instead of guessing.
  #
  # A repeat of a booking still waiting on therapist approval waits too
  # (BR-15); repeating is never a way to confirm a request.
  class RepeatAppointment < ApplicationService
    Invalid = Class.new(StandardError)

    # Carries the failing dates, e.g. [{ starts_at:, code: "therapist_not_on_shift" }].
    class Unavailable < StandardError
      attr_reader :dates

      def initialize(dates)
        @dates = dates
        super("repeat_dates_unavailable")
      end
    end

    def initialize(appointment:, interval_weeks:, count:, actor: nil)
      @appointment = appointment
      @interval = interval_weeks.to_i
      @count = count.to_i
      @actor = actor
    end

    def call
      raise Invalid, "cannot_repeat_#{@appointment.status}" unless %w[pending_approval scheduled checked_in in_progress completed].include?(@appointment.status)
      raise Invalid, "interval_weeks_must_be_1_to_4" unless (1..4).cover?(@interval)
      raise Invalid, "repeat_count_must_be_1_to_12" unless (1..12).cover?(@count)

      ImmediateTransaction.call do
        failures = []
        booked = (1..@count).filter_map do |index|
          start_at = start_for(index)
          book(start_at)
        rescue BookAppointment::Conflict, BookAppointment::Invalid => e
          failures << { starts_at: start_at.iso8601, code: e.message }
          nil
        end
        raise Unavailable, failures if failures.any?

        booked
      end
    end

    private

    def start_for(index)
      @appointment.starts_at.in_time_zone(@appointment.location.tz).advance(weeks: index * @interval)
    end

    def book(start_at)
      BookAppointment.call(
        location: @appointment.location,
        client: @appointment.client,
        actor: @actor,
        variant_ids: @appointment.appointment_items.map(&:service_variant_id),
        start_at:,
        staff_profile_ids: confirmed_staff_ids,
        requested_staff_profile_id: requested_staff_id,
        booking_channel: @appointment.booking_channel,
        client_note: @appointment.client_note,
        appointment_note: @appointment.appointment_note,
        participant_client_ids: @appointment.appointment_participants.map(&:client_id) -
                                [ @appointment.client_id ]
      )
    end

    def confirmed_staff_ids
      return nil unless @appointment.staff_assignment_confirmed?

      @appointment.staff_profiles.map(&:id)
    end

    def requested_staff_id
      return nil unless @appointment.status == "pending_approval"

      ApprovalRequest.pending.find_by(appointment_id: @appointment.id)&.requested_staff_profile_id
    end
  end
end
