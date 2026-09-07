module Api
  module V1
    class AvailabilityController < ApplicationController
      # GET /api/v1/availability
      def index
        location = scoped_location!(params.require(:location_id))
        variants = load_variants!
        from = Date.parse(params.require(:date_from))
        to   = params[:date_to].present? ? Date.parse(params[:date_to]) : from

        shape = Scheduling::AppointmentShape.call(variants:)
        days = Scheduling::AvailabilitySearch.call(
          location:, variants:, date_from: from, date_to: to,
          requested_staff_profile_id: params[:requested_staff_profile_id].presence,
          channel: params[:channel].presence || "manager"
        )

        render json: {
          location_id: location.id,
          timezone: location.timezone,
          duration_minutes: shape.duration_minutes,
          buffer_minutes: location.buffer_minutes,
          therapists_required: shape.therapist_count,
          required_client_capacity: shape.required_client_capacity,
          days: days.map { |d| { date: d[:date], slots: d[:slots].map { |s| slot_json(s) } } }
        }
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # FRS §5 / BR-16 — that therapist's next times, never a substitute.
      def next_for_therapist
        location = scoped_location!(params.require(:location_id))
        variants = load_variants!
        after = Time.zone.parse(params.require(:after))

        slots = Scheduling::NextAvailableForTherapist.call(
          location:, variants:,
          staff_profile_id: params.require(:staff_profile_id),
          after:, limit: (params[:limit] || 3).to_i
        )
        render json: { slots: slots.map { |s| slot_json(s) } }
      end

      private

      def load_variants!
        ids = Array(params[:service_variant_ids] || params[:service_variant_id])
        raise ArgumentError, "service_variant_ids is required" if ids.empty?
        variants = ServiceVariant.active.where(id: ids).includes(:service).to_a
        raise ArgumentError, "unknown service" if variants.empty?
        variants
      end

      def slot_json(slot)
        {
          start_at: slot.start_at.iso8601,
          service_end_at: slot.service_end_at.iso8601,
          end_at: slot.end_at.iso8601,
          staff: slot.staff,
          room_available_count: slot.room_ids.size
        }
      end
    end
  end
end
