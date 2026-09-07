module Api
  module V1
    class RatingsController < ApplicationController
      # The rating link needs a phone, not an account (FRS §11.2), so the
      # token-based routes are open. The kiosk sits on an in-location screen.
      skip_before_action :authenticate!, only: %i[show_by_token create_by_token]

      # GET /api/v1/public/ratings/:token — what the SMS link opens.
      def show_by_token
        appt = find_by_token!
        render json: {
          reference: appt.reference,
          therapist: appt.staff_profiles.first&.display_name,
          location: appt.location.name,
          starts_at: appt.starts_at.in_time_zone(appt.location.tz).iso8601,
          already_rated: appt.appointment_rating.present?
        }
      end

      def create_by_token
        appt = find_by_token!
        submit(appt, "sms_link")
      end

      # The in-location touchscreen: staff-authenticated, picks an appointment.
      def create
        appt = Appointment.find(params.require(:appointment_id))
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(appt.location_id)
        submit(appt, "kiosk")
      end

      # What the kiosk offers: today's completed appointments, not yet rated.
      def kiosk_queue
        location = scoped_location!(params.require(:location_id))
        appts = Appointment.on_date(location, Date.current)
                           .where(status: "completed")
                           .where.missing(:appointment_rating)
                           .includes(:client, :staff_profiles)
        render json: {
          appointments: appts.order(:starts_at).map { |a|
            { id: a.id, reference: a.reference, client_name: a.client.full_name,
              therapist: a.staff_profiles.first&.display_name,
              time: a.starts_at.in_time_zone(location.tz).strftime("%H:%M") }
          }
        }
      end

      private

      def find_by_token!
        Appointment.includes(:location, :staff_profiles, :appointment_rating)
                   .find_by!(rating_token: params.require(:token))
      end

      def submit(appt, channel)
        rating = Crm::RecordRating.call(
          appointment: appt, score: params.require(:score), channel:,
          feedback: params[:feedback], improvement: params[:improvement],
          would_recommend: params[:would_recommend]
        )
        render json: { id: rating.id, score: rating.score, thank_you: true }, status: :created
      rescue Crm::RecordRating::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end
    end
  end
end
