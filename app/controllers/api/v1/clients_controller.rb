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

      # BR-42: one client, one history. Merging repoints everything and marks
      # the loser merged — it never deletes.
      def merge
        require_owner!
        source = Client.find(params[:id])
        target = Client.find(params.require(:into_client_id))
        merged = Crm::MergeClients.call(source:, target:, actor: current_user)
        render json: client_json(merged, detail: true)
      rescue Crm::MergeClients::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
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

      def preferences
        client = Client.kept.find(params[:id])
        raise ActiveRecord::RecordNotFound unless may_read_preferences?(client)

        render json: { client_id: client.id, preference: preference_json(client.client_preference) }
      end

      # BR-43: the form is versioned, so the history is readable rather than
      # overwritten. Owner and Manager only — a therapist sees the current form.
      def preference_versions
        require_role!(:owner, :manager)
        client = Client.kept.find(params[:id])
        versions = client.client_preference_versions.order(superseded_at: :desc)

        render json: { client_id: client.id,
                       versions: versions.map { |v| preference_json(v).merge(superseded_at: v.superseded_at) } }
      end

      private

      # Doc 05: a therapist may read the form only for a client they are
      # actually seeing.
      def may_read_preferences?(client)
        return true unless current_user.staff?

        client.appointments.joins(:appointment_staff)
              .where(appointment_staff: { staff_profile_id: current_user.staff_profile&.id })
              .exists?
      end

      def preference_json(pref)
        return nil if pref.nil?

        { attention_areas: pref.attention_areas, avoid_areas: pref.avoid_areas,
          pressure: pref.pressure, other_requests: pref.other_requests }
      end

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
