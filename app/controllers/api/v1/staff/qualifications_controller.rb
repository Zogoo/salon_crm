module Api
  module V1
    module Staff
      # BR-01: a therapist needs a location and at least one qualification to be
      # schedulable. Qualification is per service, so every duration of that
      # service comes with it.
      class QualificationsController < ApplicationController
        include StaffScoped

        def show
          render json: { qualifications: qualifications_json(staff_profile!) }
        end

        # Sent as the complete set, so removing one is simply a shorter list.
        def update
          require_owner!
          profile = StaffProfile.find(params[:staff_id])
          Workforce::SetQualifications.call(
            staff_profile: profile, service_ids: params[:service_ids], actor: current_user
          )
          render json: { qualifications: qualifications_json(profile.reload) }
        rescue Workforce::SetQualifications::Invalid => e
          render_invalid(e.message)
        end

        private

        def qualifications_json(profile)
          profile.staff_qualifications.includes(:service).order("services.name").map do |q|
            { service_id: q.service_id, name: q.service.name, active: q.active }
          end
        end
      end
    end
  end
end
