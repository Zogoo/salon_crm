module Api
  module V1
    module Staff
      # FRS §4 / BR-35: the six-rung ladder, effective-dated and never edited
      # in place.
      class SessionRatesController < ApplicationController
        include StaffScoped

        def index
          profile = staff_profile!
          return render_forbidden unless may_see_rates?(profile)

          render json: { staff_profile_id: profile.id, session_rates: ladder(profile) }
        end

        def create
          require_owner!
          profile = StaffProfile.find(params[:staff_id])
          Workforce::SetSessionRates.call(
            staff_profile: profile, actor: current_user, note: params[:note],
            rates: rate_params, effective_from: params.require(:effective_from)
          )
          render json: { staff_profile_id: profile.id, session_rates: ladder(profile.reload) },
                 status: :created
        rescue Workforce::SetSessionRates::Invalid => e
          render json: { error: { code: e.message.split(":").first.strip } },
                 status: :unprocessable_content
        end

        private

        def rate_params
          params.permit(rates: %i[duration_minutes rate_cents])
                .fetch(:rates, []).map { |r| r.to_h.symbolize_keys }
        end

        def ladder(profile)
          profile.staff_session_rates.order(:effective_from, :duration_minutes).map do |r|
            { duration_minutes: r.duration_minutes, rate_cents: r.rate_cents,
              effective_from: r.effective_from, effective_to: r.effective_to, note: r.note }
          end
        end
      end
    end
  end
end
