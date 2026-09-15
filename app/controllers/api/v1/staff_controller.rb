module Api
  module V1
    class StaffController < ApplicationController
      include Listable
      include StaffScoped

      STAFF_SORTS = {
        "name" => :display_name, "code" => :employee_code,
        "hire_date" => :hire_date, "status" => :status
      }.freeze

      # Paged and searchable: a thousand people cannot be one dropdown. Pickers
      # ask for `q` and a small `limit`; the Staff screen pages through them.
      def index
        profiles = StaffProfile.where(location_id: scoped_location_ids)
                               .includes(:user, :location, :staff_session_rates)
        # The working roster by default; ?status=all reaches offboarded people.
        profiles = profiles.where(status: status_filter) unless status_filter == "all"
        if params[:q].present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.downcase.strip)}%"
          profiles = profiles.joins(:user).where(
            "LOWER(staff_profiles.display_name) LIKE :term OR LOWER(staff_profiles.employee_code) LIKE :term " \
            "OR LOWER(users.email) LIKE :term", term:
          )
        end
        profiles = profiles.joins(:user).where(users: { role: params[:role] }) if %w[staff manager].include?(params[:role])

        profiles = list_sort(profiles, STAFF_SORTS, default: "name")
        pagy, records = list_page(profiles)
        render json: { staff: records.map { |p| staff_json(p) }, meta: list_meta(pagy) }
      end

      def show
        render json: staff_json(staff_profile!, detail: true)
      end

      # Doc 05 §6: onboarding is one call — login, profile, qualifications, rates.
      def create
        require_owner!
        profile = Workforce::CreateStaff.call(attrs: staff_params, actor: current_user)
        render json: staff_json(profile, detail: true), status: :created
      rescue Workforce::CreateStaff::Invalid => e
        render_invalid(e.message)
      end

      def update
        require_owner!
        profile = StaffProfile.find(params[:id])
        Workforce::UpdateStaff.call(staff_profile: profile, attrs: staff_params, actor: current_user)
        render json: staff_json(profile.reload, detail: true)
      rescue Workforce::UpdateStaff::Invalid => e
        render_invalid(e.message)
      end

      # BR-02: blocked, not warned, while future appointments exist.
      def offboard
        require_owner!
        profile = StaffProfile.find(params[:id])
        Workforce::OffboardStaff.call(
          staff_profile: profile, actor: current_user,
          termination_date: params[:termination_date].presence || profile.location.today
        )
        render json: staff_json(profile.reload, detail: true)
      rescue Workforce::OffboardStaff::Blocked => e
        render json: { error: { code: "offboard_blocked",
                                details: { appointment_ids: e.message.split(",").map(&:to_i) } } },
               status: :locked
      end

      private

      def scoped_location_ids
        return [ scoped_location!(params[:location_id]).id ] if params[:location_id].present?
        current_user.accessible_location_ids
      end

      def status_filter = params[:status].presence || "active"

      def staff_params
        params.require(:staff).permit(
          :email, :password, :display_name, :employee_code, :location_id, :role,
          :engagement_type, :hire_date, :status, :can_edit_service_menu,
          :monthly_rate_cents, :rates_effective_from,
          service_ids: [], session_rates: %i[duration_minutes rate_cents]
        )
      end
    end
  end
end
