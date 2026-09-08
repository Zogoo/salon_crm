module Api
  module V1
    class StaffController < ApplicationController
      def index
        location = scoped_location!(params.require(:location_id))
        profiles = StaffProfile.active.where(location_id: location.id)
                               .includes(:user, :staff_session_rates).order(:display_name)
        render json: { staff: profiles.map { |p| staff_json(p) } }
      end

      def show
        profile = StaffProfile.includes(:user, :staff_session_rates, :services).find(params[:id])
        raise ActiveRecord::RecordNotFound unless visible?(profile)
        render json: staff_json(profile, detail: true)
      end

      # BR-02: blocked, not warned, while future appointments exist.
      def offboard
        require_owner!
        profile = StaffProfile.find(params[:id])
        Workforce::OffboardStaff.call(
          staff_profile: profile, actor: current_user,
          termination_date: params[:termination_date].presence || Date.current
        )
        render json: staff_json(profile.reload, detail: true)
      rescue Workforce::OffboardStaff::Blocked => e
        render json: { error: { code: "offboard_blocked",
                                details: { appointment_ids: e.message.split(",").map(&:to_i) } } },
               status: :locked
      end

      private

      def visible?(profile)
        return true if current_user.owner?
        return current_user.location_id == profile.location_id if current_user.manager?
        current_user.staff_profile&.id == profile.id
      end

      # BR-02/BR-03: rates are Owner-only. A Manager never receives the field,
      # and Staff see only their own — enforced at the serialiser, not the UI.
      def may_see_rates?(profile)
        current_user.owner? || current_user.staff_profile&.id == profile.id
      end

      def staff_json(profile, detail: false)
        json = {
          id: profile.id, display_name: profile.display_name,
          employee_code: profile.employee_code, location_id: profile.location_id,
          status: profile.status, engagement_type: profile.engagement_type
        }
        if detail
          json[:email] = profile.user.email
          json[:hire_date] = profile.hire_date
          json[:services] = profile.services.map { |s| { id: s.id, name: s.name } }
          if may_see_rates?(profile)
            json[:session_rates] = profile.staff_session_rates
                                          .order(:duration_minutes)
                                          .map { |r| { duration_minutes: r.duration_minutes,
                                                       rate_cents: r.rate_cents,
                                                       effective_from: r.effective_from } }
          end
        end
        json
      end
    end
  end
end
