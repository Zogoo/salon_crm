module Api
  module V1
    module Staff
      # BR-36: managers are on a flat monthly rate and never earn per session.
      class MonthlyRatesController < ApplicationController
        include StaffScoped
        before_action :require_owner!

        def show
          render json: payload(StaffProfile.find(params[:staff_id]))
        end

        def create
          profile = StaffProfile.find(params[:staff_id])
          return render_invalid("Managers only (BR-36)", code: "not_a_manager") unless profile.manager?

          Workforce::SetMonthlyRate.call(
            staff_profile: profile, actor: current_user, note: params[:note],
            amount_cents: params.require(:amount_cents),
            effective_from: params.require(:effective_from)
          )
          render json: payload(profile.reload), status: :created
        rescue Workforce::SetMonthlyRate::Invalid => e
          render_invalid(e.message)
        end

        private

        def payload(profile)
          { staff_profile_id: profile.id,
            monthly_rates: profile.staff_monthly_rates.order(:effective_from).map { |r|
              { amount_cents: r.amount_cents, effective_from: r.effective_from,
                effective_to: r.effective_to, note: r.note }
            } }
        end
      end
    end
  end
end
