module Api
  module V1
    module Staff
      # Addendum §8. Everyone who can see the profile can read the hours; the
      # Owner and the Manager of that location can change them.
      class WorkingHoursController < ApplicationController
        include StaffScoped

        def show
          render json: { working_hours: hours_json(staff_profile!) }
        end

        def update
          require_booking!
          profile = staff_profile!
          Workforce::SetWorkingHours.call(
            staff_profile: profile, actor: current_user,
            days: params.fetch(:working_hours, []).map { |d| d.permit(:weekday, :off, :starts_at, :ends_at) }
          )
          render json: { working_hours: hours_json(profile) }
        rescue Workforce::SetWorkingHours::Invalid => e
          render_invalid(e.message)
        end

        private

        def hours_json(profile)
          profile.staff_working_hours.reload.order(:weekday).map do |row|
            { weekday: row.weekday, off: row.off, starts_at: row.starts_at, ends_at: row.ends_at }
          end
        end
      end
    end
  end
end
