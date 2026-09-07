module Api
  module V1
    class ClientsController < ApplicationController
      include Pagy::Method

      before_action :require_booking!, only: %i[create update]

      def index
        scope = Client.kept.search(params[:search]).order(:first_name, :last_name)
        pagy, records = pagy(scope, limit: (params[:limit] || 25).to_i)
        render json: { clients: records.map { |c| client_json(c) }, meta: pagy.data_hash }
      end

      def show
        render json: client_json(Client.kept.find(params[:id]), detail: true)
      end

      def create
        client = Client.new(client_params)
        if client.save
          render json: client_json(client), status: :created
        else
          render json: { error: client.errors.full_messages }, status: :unprocessable_content
        end
      end

      def update
        client = Client.kept.find(params[:id])
        if client.update(client_params)
          render json: client_json(client)
        else
          render json: { error: client.errors.full_messages }, status: :unprocessable_content
        end
      end

      # FRS §11.1 — the preferences Form, versioned on every update (BR-43).
      def update_preferences
        client = Client.kept.find(params[:id])
        pref = client.client_preference || client.build_client_preference

        if pref.persisted?
          ClientPreferenceVersion.create!(
            client:, attention_areas: pref.attention_areas, avoid_areas: pref.avoid_areas,
            pressure: pref.pressure, other_requests: pref.other_requests,
            updated_by_user_id: pref.updated_by_user_id, superseded_at: Time.current
          )
        end

        pref.assign_attributes(preference_params.merge(updated_by_user: current_user))
        if pref.save
          render json: client_json(client.reload, detail: true)
        else
          render json: { error: pref.errors.full_messages }, status: :unprocessable_content
        end
      end

      private

      def client_params
        params.require(:client).permit(:first_name, :last_name, :phone, :email,
                                       :date_of_birth, :preferred_location_id)
      end

      def preference_params
        params.require(:preference).permit(:attention_areas, :avoid_areas, :pressure, :other_requests)
      end

      def client_json(client, detail: false)
        json = {
          id: client.id, first_name: client.first_name, last_name: client.last_name,
          full_name: client.full_name, phone: client.phone, email: client.email,
          no_show_count: client.no_show_count, late_cancel_count: client.late_cancel_count
        }
        if detail
          pref = client.client_preference
          json[:date_of_birth] = client.date_of_birth
          json[:preferred_location_id] = client.preferred_location_id
          json[:preference] = pref && {
            attention_areas: pref.attention_areas, avoid_areas: pref.avoid_areas,
            pressure: pref.pressure, other_requests: pref.other_requests
          }
          json[:appointments] = client.appointments.order(starts_at: :desc).limit(20).map { |a|
            { id: a.id, reference: a.reference,
              starts_at: local_iso(a.starts_at, a.location), status: a.status,
              location: a.location.name,
              therapists: a.staff_profiles.map(&:display_name) }
          }
        end
        json
      end
    end
  end
end
