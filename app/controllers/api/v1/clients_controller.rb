module Api
  module V1
    class ClientsController < ApplicationController
      include Listable

      before_action :require_booking!, only: %i[create update]

      SORTS = {
        "name" => %i[last_name first_name],
        "last_visit" => ClientsQuery.last_visit,
        "no_shows" => :no_show_count,
        "created" => :created_at
      }.freeze

      # Built for thousands of clients: searched, filtered, sorted and paged on
      # the server. `search` is still accepted for the booking screen's lookup.
      def index
        scope = ClientsQuery.new(
          Client.kept.includes(:preferred_location),
          q: params[:q].presence || params[:search], no_shows: params[:no_shows],
          membership: params[:membership], visited: params[:visited],
          location_id: params[:location_id]
        ).call
        scope = list_sort(scope, SORTS, default: "name")
        pagy, records = list_page(scope)
        render json: { clients: list_rows(records), meta: list_meta(pagy) }
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

      # Last visit, visit count and membership for a page of clients, in three
      # grouped queries rather than three per row.
      def list_rows(records)
        ids = records.map(&:id)
        completed = Appointment.where(client_id: ids, status: "completed")
        last_visits = completed.group(:client_id).maximum(:starts_at)
        visits = completed.group(:client_id).count
        members = Membership.active.where(client_id: ids).pluck(:client_id).to_set
        zone = Location.find_by(id: current_user.accessible_location_ids.first)

        records.map do |c|
          client_json(c).merge(
            last_visit_at: local_iso(last_visits[c.id], zone),
            visits_count: visits.fetch(c.id, 0),
            member: members.include?(c.id),
            preferred_location: c.preferred_location && { id: c.preferred_location_id, name: c.preferred_location.name }
          )
        end
      end

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
